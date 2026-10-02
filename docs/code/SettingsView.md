# SettingsView.swift

[← Documentation](../../DOCUMENTATION.md)

The settings sheet, a `Form` in a `NavigationStack`, opened from the gear button in [`ContentView`](ContentView.md).

```swift
.sheet(isPresented: $isShowingSettings) {
    SettingsView(settings: settings, presets: presets)
}
```

It edits [`AppSettings`](AppSettings.md) (via `@Bindable`) and reads/modifies the [`PresetStore`](Presets.md). The selected camera, lens and `EffectiveLimits` are derived from those two.

## Sections

| Section | What it does |
| --- | --- |
| **Camera & Lens** | Pickers for camera and lens (a single-lens camera disables the lens picker). Read-only ISO/shutter/aperture ranges from `limits.describe`, crop factor, focal length, and the *Simulate Lens View* toggle. The footer explains whether a leaf shutter is in effect. |
| **Limits** | For each setting, two menu pickers choose the lowest and highest value. Changing one end moves the other if they would cross. A warning shows when the limit is outside the preset range and is therefore ignored. *Remove Limits* resets all. |
| **Photos** | Album picker (*Recents only* or an album), *New Album…*, and the *Save Location* toggle. |
| **Presets** | Import presets from JSON, reset to built-in, and a collapsible JSON format example you can tap to copy. |
| **Language** | Shows the current language and opens the app's page in iOS Settings. The app follows the system language. |

## Behaviour details

- **Albums**: `loadAlbums()` runs in `.task` and requests Photos access. If denied, the footer asks for full access. The remembered album title is refreshed. `createAlbum()` creates, reloads the list and selects the new album. Errors show in an alert.
- **Import**: `.fileImporter` accepts JSON, opens the security-scoped URL, calls `presets.importPresets`, and reports the count, or the readable error from `describe(_:)`.
- **Reset**: after confirmation, `resetToBuiltIn()` is called, and if the selected camera no longer exists, camera and lens are cleared.
- **Copy**: tapping the format example writes `formatExample` to the pasteboard, shows "Copied" for 2 seconds and plays a success haptic.

## Example: importing

The JSON accepted by the importer (also shown in the app):

```json
{
  "cameras": [
    {
      "name": "Leica M6",
      "shutter": { "min": "1", "max": "1/1000", "fullStops": true },
      "lenses": [
        { "name": "Summicron 35mm f/2", "focalLength": 35,
          "aperture": { "min": 2, "max": 16 } }
      ]
    }
  ]
}
```
