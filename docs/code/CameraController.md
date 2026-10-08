# CameraController.swift

[← Documentation](../../DOCUMENTATION.md)

Runs the back camera in auto exposure and publishes what the camera picked. That reading is the light meter. It also handles lens simulation, tap-to-meter, exposure compensation, photo capture and, on phones with a LiDAR scanner, the depth for distance measurement.

## State

`@Observable` properties, only written on the main thread:

| Property | Meaning |
| --- | --- |
| `status` | `.idle`, `.running`, `.unauthorized`, `.unavailable` (no camera, e.g. Simulator). |
| `iso`, `exposureDuration`, `aperture` | The camera's current auto exposure. |
| `bias` | Exposure compensation in EV (clamped to ±3 and the device limits). |
| `isAEAFLocked` | Exposure and focus are locked. |
| `previewScale` | Below 1 when the simulated lens is wider than the phone can go; above 1 when measuring distance limits the zoom and the rest is digital. |
| `device` | The active `AVCaptureDevice`, handed to [`CameraPreview`](CameraPreview.md) so it can keep the preview upright in landscape. Set only once the session has switched to it. |
| `supportsDistance` | The phone has a LiDAR scanner (also true without a camera, where depth is simulated). |
| `isMeasuringDistance` | Distance is on and the LiDAR camera is in use (it isn't for lenses that need the ultra wide). |
| `isSwitchingCamera` | The session is moving to another camera, until the new one shows the right zoom. The viewfinder holds its last frame meanwhile, and the UI waits before saying distance can't be measured. |

`depth` is the [`DepthSensor`](DepthSensor.md) with the distance.

```swift
camera.setMeasuresDistance(true)   // LiDAR camera with depth (from the ruler button)
camera.setMeasuresDistance(false)  // back to the multi-camera device, no depth
```

`session` (`AVCaptureSession`) is exposed for [`CameraPreview`](CameraPreview.md). All session and device configuration runs on a private serial `sessionQueue`.

## From camera exposure to scene EV

The meter reads the exposure the camera chose and converts it to EV at ISO 100:

```
EV100 = log2(N² / t) − log2(ISO / 100)
```

```swift
camera.sceneEV100   // Double?, nil until the camera reports a valid exposure
```

With `.unavailable` it returns `12 - bias`, a fake evenly lit scene, so the app is usable in the Simulator. Depth is simulated too (`depth.simulate()`).

## Lifecycle

```swift
camera.start()   // asks for permission if needed, configures, starts the session and polling
camera.stop()    // stops polling and the session (called when the app goes to background)
```

`configure()` finds two back cameras: the best multi-camera device (triple, dual-wide, dual, wide), which has the ultra wide, and the LiDAR depth camera (`.builtInLiDARDepthCamera`, the main camera paired with the scanner), if the phone has one. It computes:

- `wideEquivalent`: the main camera's 35mm-equivalent focal length from `videoFieldOfView`;
- `baseZoom`: the zoom factor of the main camera on virtual devices where 1× is the ultra wide.

### Choosing the camera

`preferredDevice()` picks the LiDAR camera only while distance is on (`setMeasuresDistance`), and not for a lens wider than the main camera on a phone with an ultra wide, which needs the multi-camera device. Otherwise, and on phones without LiDAR, it is the multi-camera device, exactly as without the feature. Distance is off by default because delivering depth limits the zoom (see below).

`use(_:)` switches the session to a camera: it swaps the input, adds the depth output only for the LiDAR camera with distance on (on other cameras it would deliver depth too, which limits their zoom), and calls `selectDepthFormat(on:)`. That keeps the format the `.photo` preset chose if it has depth, otherwise takes the largest format of the same shape that has, and selects its most detailed `DepthFloat32`/`DepthFloat16` depth format. It also reads the zooms the format allows with depth (`supportedVideoZoomRangesForDepthDataDelivery`) into `depthZoomRanges`. Only then, on the main thread, are `device`, `depthZoomRanges`, `isMeasuringDistance`, `baseZoom` and the rotation coordinator updated, bias and AE lock reset and the zoom applied, so the preview never sets its rotation on the old connection. `targetDevice` is the camera in use or being switched to, so a quick second lens change doesn't switch twice.

The switch sets `isSwitchingCamera` first and starts the session work 50 ms later, so the viewfinder has frozen its last frame before the picture goes. `isSwitchingCamera` turns off 0.35 s after the new camera's zoom is set, and the live picture fades back in.

A 0.1 s `Timer` polls `iso`, `exposureDuration` and `lensAperture` from the device, read on `sessionQueue` (one poll at a time, `isPollPending`). Values are assigned only when they change so SwiftUI doesn't re-render needlessly.

## Lens simulation

```swift
camera.setEquivalentFocalLength(50)   // show a 50mm field of view
camera.setEquivalentFocalLength(nil)  // the phone's main camera as is
```

The wanted zoom is `target / wideEquivalent * baseZoom`, clamped to the device range (maximum 10× the base zoom).

- `setEquivalentFocalLength` switches cameras first when the lens needs the other one (see above).
- Too long a lens: stays at maximum zoom.
- While delivering depth, the camera only zooms within `depthZoomRanges`: `maxAvailableVideoZoomFactor` drops to their top, so a wanted zoom past it would be silently clamped (an earlier version read that maximum and the viewfinder stayed at 1×), and with discrete ranges another zoom throws. So `applyZoom()` sets the largest allowed zoom that isn't past the wanted one (`depthZoom(closestTo:in:)`) and `previewScale` becomes `wanted / zoom` (above 1): the view enlarges the picture and `framed(_:scale:)` crops the middle of the photo to match. Depth covers what the camera sees, and the view's taps already account for the enlargement, so the device point still lines up with the depth.
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

`capturePhoto()` sets the connection rotation from `RotationCoordinator` (`videoRotationAngleForHorizonLevelCapture`, which follows how the phone is physically held, so the photo comes out in the same orientation as the viewfinder), takes a JPEG with `.balanced` prioritisation, and applies `framed`. In `.unavailable` mode it returns `PhotoStamper.placeholderPhoto()`.

`PhotoCaptureDelegate` bridges the delegate callbacks to a continuation. It is stored in `captureDelegates` (keyed by `uniqueID`) until the capture finishes and resumes the continuation exactly once.

## Concurrency

Observed state is touched only on the main thread and `captureDelegates` and `input` only on `sessionQueue`, which is why the class is declared `@unchecked Sendable`.

The main thread never reads from or waits on a device or the session. Polling, zoom limits and the zoom itself, creating inputs and reading format details all run on `sessionQueue` and hand results back with `DispatchQueue.main.async`. Values the main thread needs (the ultra wide's zoom, the exposure compensation range) are read once and cached. While the session switches cameras, device reads can block, and the session can itself wait on the main thread for the preview, so a read from the main thread could freeze the app. That is what made a lens change that switched cameras hang.
