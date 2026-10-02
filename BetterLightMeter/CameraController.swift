import AVFoundation
import Observation
import UIKit

/// Runs the back camera in auto exposure and publishes the exposure the camera picked,
/// which is what the light meter reads.
@Observable
final class CameraController {
    enum Status {
        case idle, running, unauthorized, unavailable
    }

    private(set) var status: Status = .idle
    private(set) var iso: Float = 0
    private(set) var exposureDuration: Double = 0
    private(set) var aperture: Float = 0
    /// Exposure compensation in EV, like the sun slider in the Camera app.
    private(set) var bias: Float = 0
    private(set) var isAEAFLocked = false
    /// 1 normally; below 1 when the simulated lens is wider than the phone can go,
    /// meaning the picture should be drawn that much smaller inside a black frame.
    private(set) var previewScale: CGFloat = 1

    /// Range the sun slider is allowed to move in.
    let biasLimit: Float = 3

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "BetterLightMeter.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// Focal length (35mm equivalent) the viewfinder should show; nil = the phone's main camera as is.
    @ObservationIgnored private var targetEquivalent: Double?
    /// 35mm equivalent focal length of the phone's main camera (about 26mm on recent iPhones).
    @ObservationIgnored private var wideEquivalent: Double = 26
    /// Zoom factor of the main camera on the active device. Not 1 on virtual devices that
    /// include an ultra wide camera, where 1 is the ultra wide.
    @ObservationIgnored private var baseZoom: CGFloat = 1
    /// Delegates of in-flight captures, kept alive until each finishes. Accessed on `sessionQueue`.
    @ObservationIgnored private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]

    /// Scene brightness as EV at ISO 100, derived from the camera's own auto exposure.
    var sceneEV100: Double? {
        switch status {
        case .running:
            guard iso > 0, exposureDuration > 0, aperture > 0 else { return nil }
            let n = Double(aperture)
            return log2(n * n / exposureDuration) - log2(Double(iso) / 100)
        case .unavailable:
            // No camera (e.g. Simulator): pretend to look at an evenly lit scene.
            return 12 - Double(bias)
        case .idle, .unauthorized:
            return nil
        }
    }

    // MARK: - Session

    func start() {
        if device != nil {
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
            startPolling()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure() } else { self.status = .unauthorized }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        // Prefer a multi-camera device so the ultra wide is available for wide lenses.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else {
            status = .unavailable
            return
        }
        self.device = device
        if let fov = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.activeFormat.videoFieldOfView, fov > 0 {
            // Horizontal field of view against the 36mm width of a full-frame sensor.
            wideEquivalent = 18 / tan(Double(fov) * .pi / 360)
        }
        if device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
           let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            baseZoom = CGFloat(truncating: switchOver)
        } else {
            baseZoom = 1
        }
        applyZoom()
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        sessionQueue.async { [session, photoOutput] in
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .balanced
            }
            session.commitConfiguration()
            session.startRunning()

            DispatchQueue.main.async {
                self.status = .running
                self.startPolling()
            }
        }
    }

    // MARK: - Lens simulation

    /// Zooms the viewfinder to the field of view of a lens, given as a 35mm equivalent focal length.
    /// Wider than the phone can go is shown as a smaller picture in a black frame.
    func setEquivalentFocalLength(_ millimeters: Double?) {
        guard millimeters != targetEquivalent else { return }
        targetEquivalent = millimeters
        applyZoom()
    }

    private func applyZoom() {
        let wanted = CGFloat((targetEquivalent ?? wideEquivalent) / wideEquivalent) * baseZoom
        let lower = device?.minAvailableVideoZoomFactor ?? 1
        let upper = min(device?.maxAvailableVideoZoomFactor ?? 10 * baseZoom, 10 * baseZoom)
        let zoom = min(max(wanted, lower), upper)
        // Only the "too wide" case needs a border; "too long" just stays at maximum zoom.
        let scale = min(wanted / zoom, 1)
        if previewScale != scale { previewScale = scale }

        guard let device else { return }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        }
    }

    /// Draws a photo smaller on black to match what the framed viewfinder showed.
    private static func framed(_ image: UIImage, scale: CGFloat) -> UIImage {
        guard scale < 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let size = image.size
        let inner = CGRect(
            x: size.width * (1 - scale) / 2, y: size.height * (1 - scale) / 2,
            width: size.width * scale, height: size.height * scale
        )
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: inner)
        }
    }

    private func startPolling() {
        guard pollTimer == nil, device != nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let device else { return }
        // Only assign on change so SwiftUI doesn't re-render ten times a second for nothing.
        if iso != device.iso { iso = device.iso }
        let duration = device.exposureDuration.seconds
        if exposureDuration != duration { exposureDuration = duration }
        if aperture != device.lensAperture { aperture = device.lensAperture }
    }

    // MARK: - Photo

    /// Takes a photo with the current (auto) exposure, upright for how the phone is held.
    @MainActor
    func capturePhoto() async throws -> UIImage {
        let scale = previewScale
        guard status == .running else {
            return Self.framed(PhotoStamper.placeholderPhoto(), scale: scale)
        }
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90

        let photo = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                let id = settings.uniqueID
                captureDelegates[id] = PhotoCaptureDelegate { result in
                    self.sessionQueue.async { self.captureDelegates[id] = nil }
                    continuation.resume(with: result)
                }
                photoOutput.capturePhoto(with: settings, delegate: captureDelegates[id]!)
            }
        }
        return Self.framed(photo, scale: scale)
    }

    // MARK: - Focus & exposure

    /// Tap to focus/expose. With `lock`, exposure and focus are locked once they settle (AE/AF lock).
    func focusAndExpose(at devicePoint: CGPoint, lock: Bool) {
        bias = 0
        isAEAFLocked = lock
        guard let device else { return }

        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            // Points of interest must be set before the mode for them to take effect.
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
            }
            let focusMode: AVCaptureDevice.FocusMode = lock ? .autoFocus : .continuousAutoFocus
            if device.isFocusModeSupported(focusMode) {
                device.focusMode = focusMode
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(0)
            device.unlockForConfiguration()
        }

        guard lock else { return }
        // Give auto exposure a moment to converge on the new point before freezing it.
        sessionQueue.asyncAfter(deadline: .now() + 0.6) {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            device.unlockForConfiguration()
        }
    }

    /// Back to center-weighted continuous auto exposure with no compensation.
    func resetMetering() {
        focusAndExpose(at: CGPoint(x: 0.5, y: 0.5), lock: false)
    }

    func setBias(_ value: Float) {
        var limit = (-biasLimit)...biasLimit
        if let device {
            limit = max(limit.lowerBound, device.minExposureTargetBias)...min(limit.upperBound, device.maxExposureTargetBias)
        }
        let clamped = min(max(value, limit.lowerBound), limit.upperBound)
        guard clamped != bias else { return }
        bias = clamped

        guard let device else { return }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    enum CaptureError: LocalizedError {
        case noImage

        var errorDescription: String? { String(localized: "The camera didn't return an image.") }
    }

    private var completion: ((Result<UIImage, Error>) -> Void)?

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            finish(.success(image))
        } else {
            finish(.failure(CaptureError.noImage))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        // Covers failures where no photo was delivered at all.
        finish(.failure(error ?? CaptureError.noImage))
    }

    private func finish(_ result: Result<UIImage, Error>) {
        completion?(result)
        completion = nil
    }
}

// Observed state is only touched on the main thread and `captureDelegates` only on
// `sessionQueue`, so handing the controller to the session queue is safe.
extension CameraController: @unchecked Sendable {}
