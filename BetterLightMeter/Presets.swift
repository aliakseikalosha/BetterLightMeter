import Foundation
import Observation

/// Root of a presets JSON file. See `DefaultPresets.json` for an example.
struct PresetFile: Codable {
    var cameras: [CameraPreset]
}

/// A camera body. Its ISO and shutter ranges limit the meter; its lenses limit the aperture.
struct CameraPreset: Codable, Hashable, Identifiable {
    var name: String
    var iso: PresetRange?
    /// Body shutter. Omit for bodies without one (e.g. Hasselblad V), whose lenses carry the shutter.
    var shutter: PresetRange?
    var lenses: [LensPreset]

    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        iso = try container.decodeIfPresent(PresetRange.self, forKey: .iso)
        shutter = try container.decodeIfPresent(PresetRange.self, forKey: .shutter)
        lenses = try container.decodeIfPresent([LensPreset].self, forKey: .lenses) ?? []
    }
}

struct LensPreset: Codable, Hashable, Identifiable {
    var name: String
    var aperture: PresetRange?
    /// Leaf shutter built into the lens. When present it replaces the body's shutter range.
    var shutter: PresetRange?

    var id: String { name }
}

/// A range of values, written in JSON either as a single fixed value (`400`, `"1/125"`) or as
/// `{ "min": "1/500", "max": "1", "fullStops": true }`. Order of min/max doesn't matter.
/// Values may be numbers or strings: ISO `400`, shutter `"1/500"`, `"2\""`, `"2s"`, `0.5`,
/// aperture `2.8` or `"f/2.8"`.
struct PresetRange: Codable, Hashable {
    var min: Double
    var max: Double
    /// Only whole stops are available (typical for mechanical shutters).
    var fullStops: Bool

    enum CodingKeys: String, CodingKey {
        case min, max, fullStops
    }

    init(min: Double, max: Double, fullStops: Bool = false) {
        self.min = min
        self.max = max
        self.fullStops = fullStops
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? Self.decodeValue(single) {
            self.init(min: value, max: value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            min: Self.decodeValue(container.superDecoder(forKey: .min).singleValueContainer()),
            max: Self.decodeValue(container.superDecoder(forKey: .max).singleValueContainer()),
            fullStops: container.decodeIfPresent(Bool.self, forKey: .fullStops) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
        if fullStops {
            try container.encode(fullStops, forKey: .fullStops)
        }
    }

    /// Scale indices covered by this range for the given setting.
    func indexRange(for setting: ExposureSetting) -> ClosedRange<Int> {
        let a = setting.nearestIndex(forValue: min)
        let b = setting.nearestIndex(forValue: max)
        return Swift.min(a, b)...Swift.max(a, b)
    }

    private static func decodeValue(_ container: SingleValueDecodingContainer) throws -> Double {
        if let number = try? container.decode(Double.self) {
            guard number > 0 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Values must be greater than zero")
            }
            return number
        }
        let text = try container.decode(String.self)
        guard let value = parse(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Can't read value \"\(text)\"")
        }
        return value
    }

    /// Parses "1/500", "2\"", "2s", "f/2.8", "400".
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("f/") { s.removeFirst(2) } else if s.hasPrefix("f") { s.removeFirst() }
        for suffix in ["\"", "sec", "s"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
            break
        }
        s = s.trimmingCharacters(in: .whitespaces)
        let parts = s.split(separator: "/")
        let value: Double?
        if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
            value = n / d
        } else if parts.count == 1 {
            value = Double(parts[0])
        } else {
            value = nil
        }
        guard let value, value > 0 else { return nil }
        return value
    }
}

/// Built-in and imported camera presets.
@Observable
final class PresetStore {
    private(set) var cameras: [CameraPreset] = []

    private static var importedURL: URL {
        URL.applicationSupportDirectory.appending(path: "presets.json")
    }

    init() {
        cameras = Self.load(from: Self.importedURL) ?? Self.builtIn
    }

    func camera(named name: String?) -> CameraPreset? {
        cameras.first { $0.name == name }
    }

    /// Adds the cameras from a presets JSON file, replacing cameras with the same name.
    /// Returns the number of cameras imported.
    @discardableResult
    func importPresets(from data: Data) throws -> Int {
        let file = try JSONDecoder().decode(PresetFile.self, from: data)
        guard !file.cameras.isEmpty else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The file contains no cameras."])
        }
        var merged = cameras
        for camera in file.cameras {
            if let existing = merged.firstIndex(where: { $0.name == camera.name }) {
                merged[existing] = camera
            } else {
                merged.append(camera)
            }
        }
        try save(merged)
        cameras = merged
        return file.cameras.count
    }

    func resetToBuiltIn() {
        try? FileManager.default.removeItem(at: Self.importedURL)
        cameras = Self.builtIn
    }

    private func save(_ cameras: [CameraPreset]) throws {
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(PresetFile(cameras: cameras)).write(to: Self.importedURL, options: .atomic)
    }

    private static var builtIn: [CameraPreset] {
        Bundle.main.url(forResource: "DefaultPresets", withExtension: "json").flatMap(load(from:)) ?? []
    }

    private static func load(from url: URL) -> [CameraPreset]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PresetFile.self, from: data).cameras
    }
}

/// Human-readable explanation of a decoding failure.
func describe(_ error: Error) -> String {
    guard let error = error as? DecodingError else { return error.localizedDescription }
    func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
    switch error {
    case .keyNotFound(let key, let context):
        return "Missing \"\(key.stringValue)\" at \(path(context))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
        return "\(context.debugDescription) at \(path(context))"
    @unknown default:
        return error.localizedDescription
    }
}
