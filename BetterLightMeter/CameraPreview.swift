import AVFoundation
import SwiftUI
import UIKit

/// Live camera feed with the Camera app gestures: tap to focus/expose,
/// long press for AE/AF lock, vertical drag for exposure compensation.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Below 1 the picture is shrunk inside a black frame (the lens is wider than the phone's).
    var contentScale: CGFloat = 1
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
        view.setContentScale(contentScale, animated: false)

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
        uiView.setContentScale(contentScale, animated: true)
    }

    /// Gestures live on this view so they keep working in the black border;
    /// the picture itself is in `layerView`, which gets scaled.
    final class PreviewView: UIView {
        private final class LayerView: UIView {
            override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        }

        private let layerView = LayerView()
        private var scale: CGFloat = 1

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layerView.layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(layerView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Not `frame`: it is undefined while a transform is applied.
            layerView.bounds = CGRect(origin: .zero, size: bounds.size)
            layerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }

        func setContentScale(_ newScale: CGFloat, animated: Bool) {
            guard newScale != scale else { return }
            scale = newScale
            let apply = { self.layerView.transform = CGAffineTransform(scaleX: newScale, y: newScale) }
            if animated {
                UIView.animate(withDuration: 0.25, animations: apply)
            } else {
                apply()
            }
        }

        func devicePoint(for viewPoint: CGPoint) -> CGPoint {
            let point = previewLayer.captureDevicePointConverted(fromLayerPoint: convert(viewPoint, to: layerView))
            // Taps in the border land outside the picture.
            return CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
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
