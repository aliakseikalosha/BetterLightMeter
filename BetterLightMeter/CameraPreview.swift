import AVFoundation
import SwiftUI
import UIKit

/// Live camera feed with the Camera app gestures: tap to focus/expose,
/// long press for AE/AF lock, vertical drag for exposure compensation.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Point in view coordinates, point in device (0...1) coordinates.
    var onTap: (CGPoint, CGPoint) -> Void
    var onLongPress: (CGPoint, CGPoint) -> Void
    /// Vertical movement since the previous call, in points (negative = up).
    var onDrag: (CGFloat, UIGestureRecognizer.State) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let coordinator = context.coordinator
        view.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap)))
        let longPress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleLongPress))
        longPress.minimumPressDuration = 0.6
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan)))
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        func devicePoint(for viewPoint: CGPoint) -> CGPoint {
            previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        }
    }

    final class Coordinator: NSObject {
        var parent: CameraPreview

        init(parent: CameraPreview) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView else { return }
            let point = gesture.location(in: view)
            parent.onTap(point, view.devicePoint(for: point))
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view as? PreviewView else { return }
            let point = gesture.location(in: view)
            parent.onLongPress(point, view.devicePoint(for: point))
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            parent.onDrag(translation.y, gesture.state)
        }
    }
}
