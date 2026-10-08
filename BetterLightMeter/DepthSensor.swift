import AVFoundation
import Observation
import os
import QuartzCore

/// Reads the distance to one point from the LiDAR depth that comes with the camera picture.
///
/// Points are in the sensor's own orientation, like the camera's device points:
/// (0, 0) is the top left of the picture with the phone held in landscape, home side right.
@Observable
final class DepthSensor: NSObject {
    /// Metres to the measured point; nil while there is no reading.
    private(set) var distance: Double?

    @ObservationIgnored let output = AVCaptureDepthDataOutput()

    /// Readings per second; plenty for a number to read and keeps the work small.
    private static let rate: Double = 10
    /// Half the side, in depth pixels, of the square around the point whose median is the distance.
    private static let sampleRadius = 3

    private struct Request {
        var point = CGPoint(x: 0.5, y: 0.5)
        /// Off while the camera can't deliver depth, so a frame already in flight isn't published.
        var isActive = false
    }

    @ObservationIgnored private let queue = DispatchQueue(label: "BetterLightMeter.depth")
    @ObservationIgnored private let request = OSAllocatedUnfairLock(initialState: Request())
    /// Accessed on `queue`.
    @ObservationIgnored private var lastReading: CFTimeInterval = 0
    /// Made-up depth used when there's no camera (e.g. Simulator). Main thread only.
    @ObservationIgnored private var simulatedScene: [Float]?
    private static let simulatedWidth = 320
    private static let simulatedHeight = 240

    override init() {
        super.init()
        output.isFilteringEnabled = true
        output.alwaysDiscardsLateDepthData = true
        output.setDelegate(self, callbackQueue: queue)
    }

    // MARK: - Control (main thread)

    /// Measures at a point in device coordinates (0...1), the same as the camera's point of interest.
    func measure(at point: CGPoint) {
        request.withLock { $0.point = point }
        refreshSimulation()
    }

    /// Whether depth is arriving; turning it off clears the reading.
    func setActive(_ isActive: Bool) {
        request.withLock { $0.isActive = isActive }
        if isActive {
            refreshSimulation()
        } else {
            distance = nil
        }
    }

    /// Without a camera: pretends to look at a floor going away from the phone,
    /// with something round 1.8 m away in the middle. Measures once made active.
    func simulate() {
        let width = Self.simulatedWidth, height = Self.simulatedHeight
        var scene = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x - width / 2), dy = Float(y - height / 2)
                let isObject = dx * dx + dy * dy < Float(height * height) * 0.04
                // Sensor x runs from the top of the upright picture to the bottom.
                scene[y * width + x] = isObject ? 1.8 : 6 - 5.2 * Float(x) / Float(width - 1)
            }
        }
        simulatedScene = scene
        refreshSimulation()
    }

    private func refreshSimulation() {
        guard let scene = simulatedScene else { return }
        let current = request.withLock { $0 }
        let distance = scene.withUnsafeBytes { bytes in
            Self.distance(in: DepthMap(
                base: bytes.baseAddress!, width: Self.simulatedWidth, height: Self.simulatedHeight,
                bytesPerRow: Self.simulatedWidth * MemoryLayout<Float32>.size
            ), at: current.point)
        }
        publish(distance)
    }

    // MARK: - Reading

    private struct DepthMap {
        let base: UnsafeRawPointer
        let width: Int
        let height: Int
        let bytesPerRow: Int

        func depth(_ x: Int, _ y: Int) -> Float {
            base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)[x]
        }
    }

    /// The median of a small square around the point, which ignores the odd stray value at an edge.
    private static func distance(in map: DepthMap, at point: CGPoint) -> Double? {
        let cx = Int((point.x * CGFloat(map.width - 1)).rounded())
        let cy = Int((point.y * CGFloat(map.height - 1)).rounded())
        var samples: [Float] = []
        for y in max(0, cy - sampleRadius)...min(map.height - 1, cy + sampleRadius) {
            for x in max(0, cx - sampleRadius)...min(map.width - 1, cx + sampleRadius) {
                let depth = map.depth(x, y)
                if depth.isFinite, depth > 0 { samples.append(depth) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        // Centimetres are as fine as it gets; rounding also spares redraws for nothing.
        return (Double(samples[samples.count / 2]) * 100).rounded() / 100
    }

    /// Main thread.
    private func publish(_ newDistance: Double?) {
        guard request.withLock({ $0.isActive }) else { return }
        if distance != newDistance { distance = newDistance }
    }
}

extension DepthSensor: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastReading >= 1 / Self.rate else { return }
        lastReading = now

        let current = request.withLock { $0 }
        guard current.isActive else { return }
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = depth.depthDataMap
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let map = DepthMap(
            base: base,
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
        )
        let distance = Self.distance(in: map, at: current.point)
        DispatchQueue.main.async { self.publish(distance) }
    }
}

// Observed state is only touched on the main thread, `lastReading` only on `queue`,
// and what both share is behind `request`'s lock.
extension DepthSensor: @unchecked Sendable {}
