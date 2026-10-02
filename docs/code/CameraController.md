# CameraController.swift

[← Documentation](../../DOCUMENTATION.md)

Runs the back camera in auto exposure and publishes what the camera picked. That reading is the light meter. It also handles lens simulation, tap-to-meter, exposure compensation and photo capture.

## State

`@Observable` properties, only written on the main thread:

| Property | Meaning |
| --- | --- |
| `status` | `.idle`, `.running`, `.unauthorized`, `.unavailable` (no camera, e.g. Simulator). |
| `iso`, `exposureDuration`, `aperture` | The camera's current auto exposure. |
| `bias` | Exposure compensation in EV (clamped to ±3 and the device limits). |
| `isAEAFLocked` | Exposure and focus are locked. |
| `previewScale` | Below 1 when the simulated lens is wider than the phone can go. |

`session` (`AVCaptureSession`) is exposed for [`CameraPreview`](CameraPreview.md). All session and device configuration runs on a private serial `sessionQueue`.

## From camera exposure to scene EV

The meter reads the exposure the camera chose and converts it to EV at ISO 100:

```
EV100 = log2(N² / t) − log2(ISO / 100)
```

```swift
camera.sceneEV100   // Double?, nil until the camera reports a valid exposure
```

With `.unavailable` it returns `12 - bias`, a fake evenly lit scene, so the app is usable in the Simulator.

## Lifecycle

```swift
camera.start()   // asks for permission if needed, configures, starts the session and polling
camera.stop()    // stops polling and the session (called when the app goes to background)
```

`configure()` picks the best back device (triple, dual-wide, dual, wide) so the ultra wide is available for wide lenses. It computes:

- `wideEquivalent`: the main camera's 35mm-equivalent focal length from `videoFieldOfView`;
- `baseZoom`: the zoom factor of the main camera on virtual devices where 1× is the ultra wide.

A 0.1 s `Timer` polls `iso`, `exposureDuration` and `lensAperture` from the device. Values are assigned only when they change so SwiftUI doesn't re-render needlessly.

## Lens simulation

```swift
camera.setEquivalentFocalLength(50)   // show a 50mm field of view
camera.setEquivalentFocalLength(nil)  // the phone's main camera as is
```

The wanted zoom is `target / wideEquivalent * baseZoom`, clamped to the device range (maximum 10× the base zoom).

- Too long a lens: stays at maximum zoom.
- Too wide a lens: zoom stops at the minimum and `previewScale` becomes `wanted / zoom` (below 1). The view draws the picture smaller inside a black border, and `framed(_:scale:)` does the same to the captured photo.

## Metering gestures

```swift
// Tap: continuous AF/AE at a point (devicePoint is in 0...1 camera space)
camera.focusAndExpose(at: CGPoint(x: 0.3, y: 0.6), lock: false)

// Long press: focus, then lock exposure after 0.6 s so AE can settle first
camera.focusAndExpose(at: point, lock: true)

camera.setBias(1.0)      // +1 EV, like the Camera app's sun slider
camera.resetMetering()   // centre point, continuous AE, bias 0
```

## Taking a photo

```swift
let image = try await camera.capturePhoto()
```

`capturePhoto()` sets the connection rotation from `RotationCoordinator`, takes a JPEG with `.balanced` prioritisation, and applies `framed`. In `.unavailable` mode it returns `PhotoStamper.placeholderPhoto()`.

`PhotoCaptureDelegate` bridges the delegate callbacks to a continuation. It is stored in `captureDelegates` (keyed by `uniqueID`) until the capture finishes and resumes the continuation exactly once.

## Concurrency

Observed state is touched only on the main thread and `captureDelegates` only on `sessionQueue`, which is why the class is declared `@unchecked Sendable`.
