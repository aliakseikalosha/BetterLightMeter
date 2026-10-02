import Foundation
import Observation

/// A list of standard 1/3-stop values for one exposure setting.
///
/// Every setting is expressed in "stops" so the exposure equation becomes a simple sum:
///   aperture  a = log2(N²)       (f/1 = 0)
///   shutter   s = log2(1 / t)    (1" = 0)
///   ISO       i = log2(ISO / 100) (ISO 100 = 0)
///   EV100 = a + s - i
struct StopScale {
    let labels: [String]
    /// Stops value of the first entry in `labels`; every following entry adds 1/3 stop.
    let firstStop: Double

    func stops(at index: Int) -> Double {
        firstStop + Double(index) / 3
    }

    func nearestIndex(toStops stops: Double) -> Int {
        let raw = Int(((stops - firstStop) * 3).rounded())
        return min(max(raw, 0), labels.count - 1)
    }
}

enum ExposureSetting: CaseIterable, Identifiable {
    case iso, shutter, aperture

    var id: Self { self }

    var title: String {
        switch self {
        case .iso: "ISO"
        case .shutter: "SHUTTER"
        case .aperture: "APERTURE"
        }
    }

    var displayName: String {
        switch self {
        case .iso: "ISO"
        case .shutter: "Shutter Speed"
        case .aperture: "Aperture"
        }
    }

    /// Sign of this setting's contribution to EV100 (`EV100 = a + s - i`).
    var evSign: Double { self == .iso ? -1 : 1 }

    var scale: StopScale {
        switch self {
        case .iso: Self.isoScale
        case .shutter: Self.shutterScale
        case .aperture: Self.apertureScale
        }
    }

    private static let isoScale = StopScale(
        labels: ["25", "32", "40", "50", "64", "80", "100", "125", "160", "200", "250", "320",
                 "400", "500", "640", "800", "1000", "1250", "1600", "2000", "2500", "3200",
                 "4000", "5000", "6400", "8000", "10000", "12800", "16000", "20000", "25600"],
        firstStop: -2
    )

    private static let shutterScale = StopScale(
        labels: ["30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"", "6\"", "5\"", "4\"",
                 "3.2\"", "2.5\"", "2\"", "1.6\"", "1.3\"", "1\"", "0.8\"", "0.6\"", "1/2",
                 "0.4\"", "0.3\"", "1/4", "1/5", "1/6", "1/8", "1/10", "1/13", "1/15", "1/20",
                 "1/25", "1/30", "1/40", "1/50", "1/60", "1/80", "1/100", "1/125", "1/160",
                 "1/200", "1/250", "1/320", "1/400", "1/500", "1/640", "1/800", "1/1000",
                 "1/1250", "1/1600", "1/2000", "1/2500", "1/3200", "1/4000", "1/5000",
                 "1/6400", "1/8000"],
        firstStop: -5
    )

    private static let apertureScale = StopScale(
        labels: ["f/1.0", "f/1.1", "f/1.2", "f/1.4", "f/1.6", "f/1.8", "f/2", "f/2.2", "f/2.5",
                 "f/2.8", "f/3.2", "f/3.5", "f/4", "f/4.5", "f/5", "f/5.6", "f/6.3", "f/7.1",
                 "f/8", "f/9", "f/10", "f/11", "f/13", "f/14", "f/16", "f/18", "f/20", "f/22",
                 "f/25", "f/29", "f/32"],
        firstStop: 0
    )
}

extension ExposureSetting {
    /// Converts a physical value (ISO, seconds, f-number) to stops on this setting's scale.
    func stops(forValue value: Double) -> Double {
        switch self {
        case .iso: log2(value / 100)
        case .shutter: log2(1 / value)
        case .aperture: log2(value * value)
        }
    }

    func nearestIndex(forValue value: Double) -> Int {
        scale.nearestIndex(toStops: stops(forValue: value))
    }

    var allIndices: [Int] {
        Array(scale.labels.indices)
    }

    /// Names for the low / high end of the scale, in scale order.
    var limitTitles: (low: String, high: String) {
        switch self {
        case .iso: ("Lowest", "Highest")
        case .shutter: ("Slowest", "Fastest")
        case .aperture: ("Widest", "Narrowest")
        }
    }
}

/// Holds the user's ISO / shutter / aperture choice and keeps it matched to the metered scene.
///
/// Up to two settings can be locked; a locked setting keeps its value. When the scene or a
/// setting changes, one unlocked setting compensates: the one the user touched least recently.
/// Every setting can still be changed by hand. Changing the only unlocked one switches it to
/// manual, so nothing compensates until it's reset to automatic.
/// Each setting can only take the values in `allowed` (user limits and camera/lens presets).
@Observable
final class ExposureModel {
    static let maxLocks = 2

    private(set) var indices: [ExposureSetting: Int] = [.iso: 6, .shutter: 36, .aperture: 18]
    /// Locked settings, oldest lock first.
    private(set) var locks: [ExposureSetting] = [.aperture]
    /// Metered scene brightness, EV at ISO 100.
    private(set) var sceneEV: Double = 12
    /// While held, live meter readings are ignored.
    private(set) var isHeld = false
    /// Scale indices each setting may use, ascending.
    private(set) var allowed: [ExposureSetting: [Int]] = [:]

    /// Settings the user changed, most recent last.
    private var touchOrder: [ExposureSetting] = []
    /// The only unlocked setting, after the user set it by hand instead of letting it compensate.
    private var manualOverride: ExposureSetting?

    init() {
        compensate()
    }

    func isLocked(_ setting: ExposureSetting) -> Bool {
        locks.contains(setting)
    }

    func allowedIndices(for setting: ExposureSetting) -> [Int] {
        allowed[setting] ?? setting.allIndices
    }

    /// A setting limited to a single value (e.g. a fixed film speed) can't change at all.
    func isFixed(_ setting: ExposureSetting) -> Bool {
        allowedIndices(for: setting).count == 1
    }

    /// The setting that is currently adjusted automatically to keep the exposure correct,
    /// or nil while the user has set the only unlocked one by hand.
    var adjusting: ExposureSetting? {
        let candidate = autoCandidate
        return candidate == manualOverride ? nil : candidate
    }

    /// Whether the user can scroll this setting. Only single-value settings can't change.
    func isEditable(_ setting: ExposureSetting) -> Bool {
        !isFixed(setting)
    }

    /// Whether `resetToAuto` would do anything for this setting.
    func canResetToAuto(_ setting: ExposureSetting) -> Bool {
        !isLocked(setting) && !isFixed(setting) && adjusting != setting
    }

    func index(of setting: ExposureSetting) -> Int {
        indices[setting] ?? 0
    }

    func label(of setting: ExposureSetting) -> String {
        setting.scale.labels[index(of: setting)]
    }

    /// EV100 produced by the currently selected settings.
    var settingsEV: Double {
        ExposureSetting.allCases.reduce(0) { $0 + $1.evSign * stops(of: $1) }
    }

    /// How far the selected settings are from the metered exposure. Positive = overexposed.
    var deviation: Double {
        sceneEV - settingsEV
    }

    func select(_ index: Int, for setting: ExposureSetting) {
        guard isEditable(setting), indices[setting] != index,
              allowedIndices(for: setting).contains(index) else { return }
        indices[setting] = index
        touchOrder.removeAll { $0 == setting }
        touchOrder.append(setting)
        // Still the auto candidate after being touched last: it's the only unlocked one.
        if autoCandidate == setting {
            manualOverride = setting
        }
        compensate()
    }

    /// Makes an unlocked setting the automatically adjusted one again.
    func resetToAuto(_ setting: ExposureSetting) {
        guard !isLocked(setting), !isFixed(setting) else { return }
        manualOverride = nil
        // Count every other setting as touched more recently, so this one compensates.
        touchOrder.removeAll { $0 == setting }
        let untouched = ExposureSetting.allCases.filter { $0 != setting && !touchOrder.contains($0) }
        touchOrder = [setting] + untouched + touchOrder
        compensate()
    }

    /// Locks or unlocks a setting. Locking a third one releases the oldest lock.
    func toggleLock(_ setting: ExposureSetting) {
        if isLocked(setting) {
            locks.removeAll { $0 == setting }
        } else {
            if locks.count == Self.maxLocks {
                locks.removeFirst()
            }
            locks.append(setting)
        }
        manualOverride = nil
        compensate()
    }

    /// Restricts the values each setting may take, moving current values into range.
    func setAllowed(_ newAllowed: [ExposureSetting: [Int]]) {
        guard newAllowed != allowed else { return }
        allowed = newAllowed
        for setting in ExposureSetting.allCases {
            indices[setting] = nearestAllowed(for: setting, toStops: stops(of: setting))
        }
        compensate()
    }

    func updateScene(ev: Double) {
        // Small threshold keeps the auto-adjusted wheel from flickering on sensor noise.
        guard !isHeld, abs(ev - sceneEV) >= 0.1 else { return }
        sceneEV = ev
        compensate()
    }

    func setHeld(_ held: Bool, currentEV: Double?) {
        isHeld = held
        if !held, let currentEV {
            updateScene(ev: currentEV)
        }
    }

    /// Least recently touched unlocked setting. Never-touched settings go first,
    /// preferring shutter, then aperture, then ISO.
    private var autoCandidate: ExposureSetting {
        let preference: [ExposureSetting] = [.shutter, .aperture, .iso]
        let unlocked = preference.filter { !isLocked($0) }
        let movable = unlocked.filter { !isFixed($0) }
        let candidates = movable.isEmpty ? unlocked : movable
        return candidates.min { recency(of: $0) < recency(of: $1) } ?? .shutter
    }

    private func recency(of setting: ExposureSetting) -> Int {
        touchOrder.firstIndex(of: setting) ?? -1
    }

    private func stops(of setting: ExposureSetting) -> Double {
        setting.scale.stops(at: index(of: setting))
    }

    private func nearestAllowed(for setting: ExposureSetting, toStops target: Double) -> Int {
        let scale = setting.scale
        return allowedIndices(for: setting).min {
            abs(scale.stops(at: $0) - target) < abs(scale.stops(at: $1) - target)
        } ?? scale.nearestIndex(toStops: target)
    }

    private func compensate() {
        guard let target = adjusting else { return }
        let others = ExposureSetting.allCases
            .filter { $0 != target }
            .reduce(0) { $0 + $1.evSign * stops(of: $1) }
        // sceneEV = others + sign * targetStops, and sign is ±1.
        let needed = (sceneEV - others) * target.evSign
        indices[target] = nearestAllowed(for: target, toStops: needed)
    }
}
