import Foundation
import Observation

/// User options, persisted in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Preset selected on first launch.
    static let defaultCameraName = "Minolta X-700"
    static let defaultLensName = "Minolta MD 28mm f/2.8"

    /// User limits per setting, as scale indices.
    private(set) var limits: [ExposureSetting: ClosedRange<Int>] = [:]

    var cameraName: String? {
        didSet { defaults.set(cameraName ?? "", forKey: "cameraName") }
    }

    var lensName: String? {
        didSet { defaults.set(lensName ?? "", forKey: "lensName") }
    }

    /// Photos album to save to; nil saves to the library only.
    var albumID: String? {
        didSet { defaults.set(albumID, forKey: "albumID") }
    }

    var albumTitle: String? {
        didSet { defaults.set(albumTitle, forKey: "albumTitle") }
    }

    init() {
        // nil = never chosen (use the default), "" = the user picked "None".
        if let storedCamera = defaults.string(forKey: "cameraName") {
            cameraName = storedCamera.isEmpty ? nil : storedCamera
            lensName = defaults.string(forKey: "lensName").flatMap { $0.isEmpty ? nil : $0 }
        } else {
            cameraName = Self.defaultCameraName
            lensName = Self.defaultLensName
        }
        albumID = defaults.string(forKey: "albumID")
        albumTitle = defaults.string(forKey: "albumTitle")
        for setting in ExposureSetting.allCases {
            let full = setting.allIndices
            let low = defaults.object(forKey: "limit.\(setting).low") as? Int ?? full.first!
            let high = defaults.object(forKey: "limit.\(setting).high") as? Int ?? full.last!
            limits[setting] = clamped(low, high, for: setting)
        }
    }

    /// Picks a camera preset and its first lens.
    func selectCamera(_ camera: CameraPreset?) {
        cameraName = camera?.name
        lensName = camera?.lenses.first?.name
    }

    func limit(for setting: ExposureSetting) -> ClosedRange<Int> {
        limits[setting] ?? 0...(setting.allIndices.count - 1)
    }

    func setLimit(low: Int, high: Int, for setting: ExposureSetting) {
        let range = clamped(low, high, for: setting)
        limits[setting] = range
        defaults.set(range.lowerBound, forKey: "limit.\(setting).low")
        defaults.set(range.upperBound, forKey: "limit.\(setting).high")
    }

    func resetLimits() {
        for setting in ExposureSetting.allCases {
            setLimit(low: 0, high: setting.allIndices.count - 1, for: setting)
        }
    }

    private func clamped(_ low: Int, _ high: Int, for setting: ExposureSetting) -> ClosedRange<Int> {
        let last = setting.allIndices.count - 1
        let a = min(max(low, 0), last)
        let b = min(max(high, 0), last)
        return min(a, b)...max(a, b)
    }
}

/// Combines the selected camera/lens preset with the user's own limits.
struct EffectiveLimits {
    let camera: CameraPreset?
    let lens: LensPreset?
    let settings: AppSettings

    /// The preset range that applies to a setting: ISO and shutter from the body,
    /// aperture from the lens, and a lens' leaf shutter overrides the body's shutter.
    func presetRange(for setting: ExposureSetting) -> PresetRange? {
        switch setting {
        case .iso: camera?.iso
        case .shutter: lens?.shutter ?? camera?.shutter
        case .aperture: lens?.aperture
        }
    }

    /// Whether the user's limit had to be ignored because it doesn't overlap the preset.
    func userLimitConflicts(for setting: ExposureSetting) -> Bool {
        guard let preset = presetRange(for: setting)?.indexRange(for: setting) else { return false }
        return !preset.overlaps(settings.limit(for: setting))
    }

    func allowedIndices(for setting: ExposureSetting) -> [Int] {
        let preset = presetRange(for: setting)
        let presetIndices = preset?.indexRange(for: setting) ?? 0...(setting.allIndices.count - 1)
        let user = settings.limit(for: setting)
        let range = presetIndices.overlaps(user) ? presetIndices.clamped(to: user) : presetIndices

        guard preset?.fullStops == true else { return Array(range) }
        // Every scale starts on a whole stop, so whole stops are every third index.
        // Range ends stay available, e.g. an f/3.5 lens wide open.
        return range.filter { $0 % 3 == 0 || $0 == range.lowerBound || $0 == range.upperBound }
    }

    var all: [ExposureSetting: [Int]] {
        Dictionary(uniqueKeysWithValues: ExposureSetting.allCases.map { ($0, allowedIndices(for: $0)) })
    }

    func describe(_ setting: ExposureSetting) -> String {
        let indices = allowedIndices(for: setting)
        guard let first = indices.first, let last = indices.last else { return "–" }
        let labels = setting.scale.labels
        var text = first == last ? labels[first] : "\(labels[first]) – \(labels[last])"
        if presetRange(for: setting)?.fullStops == true {
            text += ", full stops"
        }
        return text
    }
}
