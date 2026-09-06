import AVFoundation
import Combine
import UIKit

@MainActor final class RecordingModel: ObservableObject {
    @Published private(set) var state = RecordingState()
    @Published var scrolling = false
    @Published var resetToken = 0
    @Published private(set) var frontCamera = true
    @Published private(set) var switchingCamera = false
    @Published var errorMessage: String?
    @Published var interruptionMessage: String?
    @Published var needsSettings = false
    @Published private(set) var completedTake: Take?
    @Published private(set) var startedAt: Date?
    @Published private(set) var foreground = true
    private var countdownTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var take: Take?
    private var finalizing = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    let library: LibraryStore
    let title: String
    let text: String
    lazy var camera = CameraService { [weak self] event in self?.handle(event) }
    var phase: RecordingPhase { state.phase }
    var canDismiss: Bool { !phase.locksControls && !switchingCamera }

    init(script: Script, library: LibraryStore) {
        self.library = library
        title = script.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Без названия" : script.title
        text = script.text
    }

    func prepare() {
        guard preparationTask == nil, foreground else { return }
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer { preparationTask = nil }
            for media: AVMediaType in [.video, .audio] {
                var authorized = AVCaptureDevice.authorizationStatus(for: media) == .authorized
                if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
                    authorized = await AVCaptureDevice.requestAccess(for: media)
                }
                guard authorized else {
                    needsSettings = true
                    errorMessage = "Для записи разрешите доступ к камере и микрофону в настройках iPhone."
                    state.apply(.fail)
                    return
                }
            }
            guard foreground, !Task.isCancelled else { return }
            do {
                try await camera.prepare()
                guard foreground, !Task.isCancelled else { camera.suspend(); return }
                state.apply(.prepared)
                UIApplication.shared.isIdleTimerDisabled = true
            } catch { errorMessage = error.localizedDescription; state.apply(.fail) }
        }
    }

    func retry() {
        guard foreground, !finalizing, phase == .failed || phase == .review || phase == .ready else { return }
        errorMessage = nil; interruptionMessage = nil; needsSettings = false
        completedTake = nil; startedAt = nil; take = nil; resetToken += 1
        state.apply(.retry)
        prepare()
    }

    func start() {
        guard foreground, phase == .ready, !switchingCamera else { return }
        scrolling = false
        let seconds = library.settings.countdown
        if seconds == 0 { startFile(); return }
        state.apply(.count(seconds))
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                state.apply(.count(remaining))
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled, foreground else { return }
            }
            startFile()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel(); countdownTask = nil
        state.apply(.cancelCountdown)
    }

    private func startFile() {
        guard foreground, state.apply(.requestStart) else { return }
        do {
            take = try library.beginTake(title: title)
            guard let take else { return }
            camera.start(url: library.files.movieURL(for: take.id), mirror: frontCamera && library.settings.mirrorVideo)
        } catch { errorMessage = "Не удалось подготовить файл: \(error.localizedDescription)"; state.apply(.fail) }
    }

    func stop() {
        scrolling = false
        guard state.apply(.stop) else { return }
        camera.stop()
    }

    func switchCamera() {
        guard phase == .ready, !switchingCamera else { return }
        scrolling = false; switchingCamera = true
        Task {
            defer { switchingCamera = false }
            do { try await camera.switchCamera(front: !frontCamera); frontCamera.toggle() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case .started:
            if state.apply(.didStart) { startedAt = Date(); scrolling = foreground }
        case .finished(_, let message):
            scrolling = false
            guard !finalizing, let take else { return }
            state.apply(.stop)
            finalizing = true
            camera.suspend()
            Task {
                let success = await library.finalize(take, note: interruptionMessage ?? message)
                finalizing = false
                endBackgroundTask()
                if success { completedTake = take; state.apply(.didFinish) }
                else { state.apply(.fail); errorMessage = take.note ?? "Не удалось сохранить дубль. Проверьте раздел «Дубли»." }
                UIApplication.shared.isIdleTimerDisabled = false
            }
        case .interrupted(let message):
            interruptionMessage = message
            if case .countdown = phase { cancelCountdown() }
            scrolling = false
            if phase == .recording || phase == .starting { stop() }
            else if phase != .finishing && phase != .review { state.apply(.fail); errorMessage = message }
        case .failure(let message):
            scrolling = false; errorMessage = message; state.apply(.fail)
            camera.suspend(); endBackgroundTask()
            UIApplication.shared.isIdleTimerDisabled = false
            if let take {
                take.status = "unavailable"; take.note = message; library.save()
            }
        }
    }

    func leaveForeground() {
        foreground = false
        scrolling = false
        // Permission sheets temporarily inactivate the app while preparation awaits authorization.
        if case .countdown = phase { cancelCountdown() }
        if phase == .recording || phase == .starting || phase == .finishing {
            interruptionMessage = "Запись остановлена при выходе из приложения."
            if backgroundTask == .invalid {
                backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinishTake") { [weak self] in
                    Task { @MainActor in self?.endBackgroundTask() }
                }
            }
            stop()
        }
        camera.suspend()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func enterForeground() {
        foreground = true
        if phase == .preparing { prepare() }
        else if phase == .ready { state.apply(.retry); prepare() }
        // Interrupted takes are never restarted automatically.
    }

    func close() {
        countdownTask?.cancel(); preparationTask?.cancel()
        scrolling = false; camera.suspend()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
