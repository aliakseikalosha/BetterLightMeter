# ContentView.swift

[← Documentation](../../DOCUMENTATION.md)

The main screen. It creates the models, wires them together and lays out the UI.

## Models

`ContentView` owns these as `@State`:

| Model | Role |
| --- | --- |
| [`CameraController`](CameraController.md) | Live camera and metering. |
| [`ExposureModel`](ExposureModel.md) | ISO/shutter/aperture and compensation. |
| [`AppSettings`](AppSettings.md) | Persisted user options. |
| [`LocationProvider`](PhotoLibrary.md) | Geotagging. |
| [`PresetStore`](Presets.md) | Camera and lens presets. |

`selectedCamera`, `selectedLens` and `limits` (`EffectiveLimits`) are computed from the settings and presets.

## Data flow

```swift
// Camera → meter: every new scene EV updates the model
.onChange(of: camera.sceneEV100) { _, ev in
    if let ev { meter.updateScene(ev: ev) }
}

// Presets/limits → meter: restrict the allowed values
.onChange(of: limits.all, initial: true) { _, allowed in
    meter.setAllowed(allowed)
}

// Lens → camera: zoom the viewfinder
.onChange(of: simulatedFocalLength, initial: true) { _, mm in
    camera.setEquivalentFocalLength(mm)
}
```

Lifecycle: the camera starts on appear and when the scene becomes active, and stops in the background. Location updates follow the `saveLocation` setting.

## Orientation

The app supports portrait and both landscapes. `isLandscape` is `verticalSizeClass == .compact`, which on iPhone is exactly "held sideways".

`body` is a single view tree for both orientations: `MeterLayout` (a private `Layout` at the bottom of the file) takes three children in order, `topBar`, `viewfinder` and `controls`, and only decides where to put them.

- **Portrait**: stacked top to bottom, `controls` at its natural height under the viewfinder.
- **Landscape**: the `viewfinder` on the left; on the right a 320 pt column (`landscapeControlsWidth`) with `topBar` above `controls`. `controls` contains a `Spacer` that pushes the shutter row to the bottom of the column and takes no height in portrait. `topBar` and `bottomBar` are a little shorter so the column fits the iPhone SE's 375 pt height.

Keep it one tree. An earlier version switched between two `if` branches, which destroyed and rebuilt the camera preview (a new preview layer and rotation coordinator on the running session) and all three wheels on every rotation, with main-thread stalls of 100–200 ms even in the Simulator. With `MeterLayout`, rotating only re-lays-out the existing views.

`focusPoint` is in viewfinder coordinates, which mean something else after rotating, so rotating clears it.

## Sections

1. **`topBar`**: scene EV, the compensation value when non-zero, an `AE/AF LOCK` or `LIVE` badge, and the settings button.
2. **`viewfinder`**: a `ZStack` of the [`CameraPreview`](CameraPreview.md), a placeholder (camera unavailable, or a permission prompt with *Open Settings*), the [`FocusIndicator`](MeterViews.md), the camera readout (ISO, shutter and aperture the phone chose, and the simulated focal length), the gear/lens menu, a toast, and the white capture flash.
3. **`controls`**, which holds the next three:
   - [`ExposureScale`](MeterViews.md) showing the deviation.
   - Three [`SettingRow`](MeterViews.md)s (`settingRows`).
   - **`bottomBar`**: last-photo thumbnail (opens Photos), [`ShutterButton`](MeterViews.md), and a reset-metering button.

## Interactions

- **Tap / long press** set `focusPoint` and call `camera.focusAndExpose(at:lock:)`.
- **Drag** changes compensation: `bias -= deltaY / 110` (110 points per EV). The focus indicator appears at the centre if there is none, and shows its track while dragging.
- The focus indicator dims after 2 s without interaction (`interactionCount` restarts a `.task(id:)`).
- Toasts disappear after 2.5 s.

## takePicture()

1. Ignores the press if a capture is running. Flashes the screen.
2. Snapshots the reading *at press time*: the headline (`ISO 400   1/125   f/8`), the details line (EV, deviation, camera, lens, date), `PhotoMetadata`, album and location.
3. In a `Task`: `camera.capturePhoto()` → stamp and JPEG-encode off the main actor (`PhotoStamper.stamp`) → `metadata.embedded(in:)` → `PhotoLibrary.save`.
4. Updates the thumbnail and shows "Saved to …", or an error toast.

```swift
let photo = try await camera.capturePhoto()
let jpeg = PhotoStamper.stamp(photo, headline: headline, details: detailsLine)
    .jpegData(compressionQuality: 0.92)
try await PhotoLibrary.save(jpeg: metadata.embedded(in: jpeg!),
                            toAlbum: albumID, location: photoLocation)
```

`shutterText(_:)` formats the phone's own exposure time (`1/250`, or `0.8"` for half a second and longer).
