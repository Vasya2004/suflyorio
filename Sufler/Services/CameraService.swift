import AVFoundation
import Foundation

enum CameraEvent: Sendable {
    case started
    case finished(URL, String?)
    case interrupted(String)
    case failure(String)
}

enum CameraFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

/// All capture configuration and mutable state belong exclusively to `queue`.
/// The preview layer receives the session reference but never configures it.
final class CameraService: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.sufler.capture", qos: .userInitiated)
    private let output = AVCaptureMovieFileOutput()
    private let sink: @MainActor @Sendable (CameraEvent) -> Void
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false
    private var wantsRunning = false
    private var activeURL: URL?
    private var stopAfterStart = false
    private var tokens: [NSObjectProtocol] = []

    init(sink: @escaping @MainActor @Sendable (CameraEvent) -> Void) {
        self.sink = sink
        super.init()
        observe()
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }

    private func emit(_ event: CameraEvent) {
        let sink = sink
        Task { @MainActor in sink(event) }
    }

    private func observe() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.interrupt("Камера или микрофон временно недоступны. Запись остановлена.")
        })
        tokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.interrupt("Сбой камеры. Сохраните доступный дубль и повторно откройте камеру.")
        })
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] note in
            let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if value == AVAudioSession.InterruptionType.began.rawValue {
                self?.interrupt("Звук прерван звонком или другим приложением. Запись остановлена.")
            }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            self?.interrupt("Аудиоустройство отключено. Проверьте звук перед новым дублем.")
        })
        tokens.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            if ProcessInfo.processInfo.thermalState == .critical {
                self?.interrupt("iPhone перегрелся. Дайте ему остыть перед следующим дублем.")
            }
        })
    }

    private func interrupt(_ message: String) {
        queue.async { [self] in
            guard wantsRunning || activeURL != nil else { return }
            wantsRunning = false
            requestStopOnQueue()
            if activeURL == nil { stopSessionOnQueue() }
            emit(.interrupted(message))
        }
    }

    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard activeURL == nil else { throw CameraFailure.message("Предыдущий дубль ещё сохраняется.") }
                    let audio = AVAudioSession.sharedInstance()
                    try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                    try audio.setActive(true)
                    guard let microphone = audio.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                        throw CameraFailure.message("Встроенный микрофон недоступен.")
                    }
                    try audio.setPreferredInput(microphone)
                    if !configured { try configureOnQueue() }
                    wantsRunning = true
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning, !session.isInterrupted else {
                        throw CameraFailure.message("Не удалось запустить камеру. Закройте приложения, использующие камеру, и повторите.")
                    }
                    continuation.resume()
                } catch {
                    wantsRunning = false
                    stopSessionOnQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // A previous configuration attempt can have failed partway through.
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.automaticallyConfiguresApplicationAudioSession = false
        session.usesApplicationAudioSession = true
        guard session.canSetSessionPreset(.hd1920x1080) else { throw CameraFailure.message("Запись Full HD недоступна.") }
        session.sessionPreset = .hd1920x1080
        let video = try makeVideoInput(position: .front)
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw CameraFailure.message("Микрофон не найден.") }
        let audio = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(video) else { throw CameraFailure.message("Камера недоступна.") }
        session.addInput(video)
        guard session.canAddInput(audio) else { throw CameraFailure.message("Не удалось подключить микрофон.") }
        session.addInput(audio)
        guard session.canAddOutput(output) else { throw CameraFailure.message("Не удалось настроить запись.") }
        session.addOutput(output)
        output.minFreeDiskSpaceLimit = 100 * 1_024 * 1_024
        try setFrameRate(video.device)
        try configureConnection(mirror: false)
        videoInput = video
        configured = true
    }

    private func makeVideoInput(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraFailure.message("Выбранная камера не найдена.")
        }
        return try AVCaptureDeviceInput(device: device)
    }

    private func setFrameRate(_ device: AVCaptureDevice) throws {
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) else {
            throw CameraFailure.message("Камера не поддерживает 30 кадров/с в выбранном режиме.")
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
        }
    }

    private func configureConnection(mirror: Bool) throws {
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90),
              output.availableVideoCodecTypes.contains(.h264) else { throw CameraFailure.message("Формат записи H.264 недоступен.") }
        // The whole application is portrait-only. Freeze the capture transform for every take.
        connection.videoRotationAngle = 90
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = mirror }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
        output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
        // AVCaptureMovieFileOutput supplies AAC audio for the connected microphone.
    }

    func switchCamera(front: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard activeURL == nil, let previous = videoInput else { throw CameraFailure.message("Камера занята.") }
                    let replacement = try makeVideoInput(position: front ? .front : .back)
                    session.beginConfiguration()
                    session.removeInput(previous)
                    guard session.canAddInput(replacement) else {
                        session.addInput(previous); session.commitConfiguration()
                        throw CameraFailure.message("Не удалось переключить камеру.")
                    }
                    session.addInput(replacement)
                    do {
                        try setFrameRate(replacement.device)
                        try configureConnection(mirror: false)
                        videoInput = replacement
                        session.commitConfiguration()
                    } catch {
                        session.removeInput(replacement)
                        if session.canAddInput(previous) { session.addInput(previous) }
                        session.commitConfiguration()
                        throw error
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func start(url: URL, mirror: Bool) {
        queue.async { [self] in
            do {
                guard configured, wantsRunning, session.isRunning, !session.isInterrupted, activeURL == nil else {
                    throw CameraFailure.message("Камера не готова к записи.")
                }
                guard ProcessInfo.processInfo.thermalState != .critical else { throw CameraFailure.message("iPhone перегрелся. Дайте ему остыть.") }
                let values = try url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                guard let available = values.volumeAvailableCapacityForImportantUsage, available > 300 * 1_024 * 1_024 else {
                    throw CameraFailure.message("Недостаточно памяти. Освободите хотя бы 300 МБ и повторите запись.")
                }
                try configureConnection(mirror: mirror)
                activeURL = url; stopAfterStart = false
                output.startRecording(to: url, recordingDelegate: self)
            } catch { emit(.failure(error.localizedDescription)) }
        }
    }

    func stop() { queue.async { [self] in requestStopOnQueue() } }

    private func requestStopOnQueue() {
        guard activeURL != nil else { return }
        stopAfterStart = true
        if output.isRecording { output.stopRecording() }
    }

    func suspend() {
        queue.async { [self] in
            wantsRunning = false
            requestStopOnQueue()
            if activeURL == nil { stopSessionOnQueue() }
        }
    }

    private func stopSessionOnQueue() {
        if session.isRunning { session.stopRunning() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { [self] in
            guard activeURL == fileURL else { return }
            emit(.started)
            if stopAfterStart || !wantsRunning { self.output.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let message = error?.localizedDescription
        queue.async { [self] in
            guard activeURL == outputFileURL else { return }
            activeURL = nil; stopAfterStart = false
            // A callback with an error may still contain a usable partial movie. The store probes it.
            wantsRunning = false
            stopSessionOnQueue()
            emit(.finished(outputFileURL, message))
        }
    }
}
