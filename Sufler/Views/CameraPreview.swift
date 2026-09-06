import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.configure(session: session, front: front)
        return view
    }

    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.configure(session: session, front: front)
    }

    static func dismantleUIView(_ view: PreviewSurface, coordinator: ()) { view.detach() }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var front = true
    private var startObserver: NSObjectProtocol?

    func configure(session: AVCaptureSession, front: Bool) {
        self.front = front
        if previewLayer.session !== session {
            detach()
            startObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applyTransform() }
            }
            previewLayer.session = session
        }
        applyTransform()
    }

    override func layoutSubviews() { super.layoutSubviews(); applyTransform() }

    private func applyTransform() {
        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
    }
    func detach() {
        if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
        startObserver = nil
        previewLayer.session = nil
    }
}
