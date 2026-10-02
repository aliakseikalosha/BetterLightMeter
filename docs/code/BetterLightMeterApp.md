# BetterLightMeterApp.swift

[← Documentation](../../DOCUMENTATION.md)

The app entry point.

## How it works

`BetterLightMeterApp` is the `@main` SwiftUI `App`. It declares a single `WindowGroup` containing [`ContentView`](ContentView.md). It owns no state: every model (`CameraController`, `ExposureModel`, `AppSettings`, `LocationProvider`, `PresetStore`) is created as `@State` inside `ContentView`.

```swift
@main
struct BetterLightMeterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Notes

- To share a model across the whole app (for example in tests or previews), create it here and pass it down with `.environment(...)` instead of creating it in `ContentView`.
