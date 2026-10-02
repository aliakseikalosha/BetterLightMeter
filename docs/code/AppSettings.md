# AppSettings.swift

[← Documentation](../../DOCUMENTATION.md)

User options persisted in `UserDefaults`, plus `EffectiveLimits`, which merges those options with the camera and lens presets.

## AppSettings

An `@Observable` class. Each property writes itself to `UserDefaults` in `didSet`.

| Property | Key | Meaning |
| --- | --- | --- |
| `cameraName`, `lensName` | `cameraName`, `lensName` | Selected presets. `nil` means "None". |
| `albumID`, `albumTitle` | `albumID`, `albumTitle` | Photos album to save to. `nil` saves to Recents only. |
| `saveLocation` | `saveLocation` | Geotag saved photos (default `true`). |
| `simulateLens` | `simulateLens` | Zoom the viewfinder to the lens' field of view (default `true`). |
| `limits` | `limit.<setting>.low/high` | Per-setting user limits as scale indices. |

### First launch vs. "None"

`defaults.string(forKey: "cameraName")` distinguishes three states:

- no value: never chosen, so the defaults (`Minolta X-700` with `Minolta MD 28mm f/2.8`) are selected;
- empty string: the user picked "None", stored as `nil`;
- a name: that preset.

### Limits

Limits are index ranges into a setting's [`StopScale`](ExposureModel.md). They are always clamped to the scale and ordered (`low <= high`).

```swift
let settings = AppSettings()

// Only allow ISO 100…1600 (indices into ExposureSetting.iso.scale.labels)
settings.setLimit(low: 6, high: 18, for: .iso)

settings.limit(for: .iso)   // 6...18
settings.resetLimits()      // every setting back to its full scale
```

`selectCamera(_:)` sets the camera and its first lens in one step:

```swift
settings.selectCamera(presets.camera(named: "Leica M6"))
```

## EffectiveLimits

A value type that combines the selected `CameraPreset`, `LensPreset` and the user's limits. It is rebuilt cheaply whenever any of them changes.

Rules in `presetRange(for:)`:

- **ISO**: from the camera body.
- **Shutter**: from the lens if it has a leaf shutter, otherwise from the camera body.
- **Aperture**: from the lens.

`allowedIndices(for:)`:

1. Start with the preset range (or the whole scale if there is no preset).
2. Intersect it with the user limit. If they don't overlap, the user limit is ignored (`userLimitConflicts(for:)` reports this so the UI can warn).
3. If the range is `fullStops`, keep every third index (scales start on a whole stop, so whole stops are multiples of 3), but always keep both ends of the range.

```swift
let limits = EffectiveLimits(camera: camera, lens: lens, settings: settings)

limits.allowedIndices(for: .shutter)  // e.g. [..] whole stops from 1" to 1/1000
limits.describe(.shutter)             // "1\" – 1/1000, full stops"
limits.userLimitConflicts(for: .iso)  // true if the user's range is outside the camera's
limits.all                            // [ExposureSetting: [Int]], passed to ExposureModel.setAllowed
```

`equivalentFocalLength` is `lens.focalLength * camera.cropFactor` and drives the viewfinder zoom in [`CameraController`](CameraController.md).
