# Presets.swift

[← Documentation](../../DOCUMENTATION.md)

Camera and lens presets: the data model, the JSON format and the store that loads and imports them.

## Data model

```swift
PresetFile      // { "cameras": [CameraPreset] }
CameraPreset    // name, iso?, shutter?, cropFactor?, lenses
LensPreset      // name, aperture?, focalLength?, shutter?
PresetRange     // min, max, fullStops
```

- A camera's `iso` and `shutter` limit the meter; a lens' `aperture` limits the aperture.
- A lens `shutter` (leaf shutter) replaces the body's. Omit the body shutter for bodies without one (e.g. Hasselblad V).
- `cropFactor` is relative to 35mm full frame (APS-C about 1.5, 6×6 about 0.55). Default 1.
- `lenses` defaults to empty when omitted.

How these are combined with user limits is described in [AppSettings](AppSettings.md).

## PresetRange JSON

A range is either a single value (a fixed setting) or an object. Values can be numbers or strings. Min/max order doesn't matter.

```json
{
  "iso": 400,
  "shutter": { "min": "1", "max": "1/1000", "fullStops": true },
  "aperture": { "min": 2.8, "max": "f/22" }
}
```

`PresetRange.parse(_:)` accepts `"1/500"`, `"2\""`, `"2s"`, `"2sec"`, `"f/2.8"`, `"f2.8"` and `"400"`. Values must be greater than zero. Failures throw a `DecodingError` with a localized description.

```swift
PresetRange.parse("1/500")   // 0.002
PresetRange.parse("f/2.8")   // 2.8
PresetRange.parse("0")       // nil

let range = PresetRange(min: 1.0 / 1000, max: 1, fullStops: true)
range.indexRange(for: .shutter)   // scale indices of the nearest values
```

Encoding writes `min`, `max` and, only when true, `fullStops`.

## PresetStore

An `@Observable` store of `cameras`.

- On init it loads `Application Support/presets.json` (imported) if valid, otherwise the bundled `DefaultPresets.json`.
- `importPresets(from:)` decodes a presets file and merges it: cameras with the same name are replaced, others are added. The merged list is saved atomically, then published. It returns the number of cameras imported and throws if the file is invalid or has no cameras.
- `resetToBuiltIn()` deletes the imported file and reloads the bundled presets.

```swift
let presets = PresetStore()

let data = try Data(contentsOf: url)
let count = try presets.importPresets(from: data)

presets.camera(named: "Leica M6")?.lenses
presets.resetToBuiltIn()
```

## describe(_:)

Turns a `DecodingError` into a readable message with the JSON path, e.g. `Missing "name" at .cameras[1]`. It is used for the import error alert in [SettingsView](SettingsView.md).
