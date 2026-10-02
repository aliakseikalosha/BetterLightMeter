# Better Light Meter Documentation

Start here. For an overview of the app, build steps and the preset JSON format, see the [README](README.md).

## How the app works

1. [`CameraController`](docs/code/CameraController.md) runs the camera in auto exposure. The exposure it picks is converted to a scene brightness (EV at ISO 100).
2. [`ExposureModel`](docs/code/ExposureModel.md) keeps ISO, shutter speed and aperture matched to that brightness. Locked settings stay put and one unlocked setting compensates.
3. [`PresetStore`](docs/code/Presets.md) and [`AppSettings`](docs/code/AppSettings.md) decide which values each setting may take (camera, lens and your own limits).
4. The shutter button captures a photo, prints the reading on it, writes EXIF and saves it through [`PhotoLibrary`](docs/code/PhotoLibrary.md).

```
CameraController ──sceneEV100──▶ ExposureModel ──▶ SettingRow / SettingWheel
                                      ▲
PresetStore + AppSettings ─▶ EffectiveLimits.all (allowed values)

shutter button ─▶ capturePhoto ─▶ PhotoStamper ─▶ PhotoMetadata ─▶ PhotoLibrary
```

## Source files

One page per Swift file in `BetterLightMeter/`.

| File | Summary |
| --- | --- |
| [BetterLightMeterApp](docs/code/BetterLightMeterApp.md) | `@main` entry point. |
| [ContentView](docs/code/ContentView.md) | Main screen; wires models together; takes pictures. |
| [CameraController](docs/code/CameraController.md) | Camera session, metering, lens simulation, capture. |
| [CameraPreview](docs/code/CameraPreview.md) | Live preview view with tap / long-press / drag gestures. |
| [ExposureModel](docs/code/ExposureModel.md) | Stops maths, locks and automatic compensation. |
| [MeterViews](docs/code/MeterViews.md) | Focus indicator, EV scale, setting rows, shutter button. |
| [SettingWheel](docs/code/SettingWheel.md) | Snapping horizontal value picker. |
| [AppSettings](docs/code/AppSettings.md) | Persisted options and `EffectiveLimits`. |
| [Presets](docs/code/Presets.md) | Preset model, JSON format, `PresetStore`. |
| [PhotoLibrary](docs/code/PhotoLibrary.md) | Saving, stamping, EXIF, location. |
| [SettingsView](docs/code/SettingsView.md) | The settings sheet. |
