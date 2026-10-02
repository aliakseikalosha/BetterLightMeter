# CameraPreview.swift

[← Documentation](../../DOCUMENTATION.md)

A `UIViewRepresentable` that shows the live camera feed and turns touches into the Camera app's gestures.

## Gestures

| Gesture | Callback | Meaning |
| --- | --- | --- |
| Tap | `onTap(viewPoint, devicePoint)` | Focus and meter at a point. |
| Long press (0.6 s) | `onLongPress(viewPoint, devicePoint)` | AE/AF lock. Fires once, on `.began`. |
| Vertical pan | `onDrag(deltaY, state)` | Exposure compensation. `deltaY` is the movement since the previous call (negative = up). |

`viewPoint` is in view coordinates (to place the focus square); `devicePoint` is normalised 0…1 camera coordinates (to pass to `CameraController.focusAndExpose`).

## Structure

`PreviewView` is the container and owns the gesture recognizers. Inside it, `layerView` has an `AVCaptureVideoPreviewLayer` as its layer. Only `layerView` is scaled when `contentScale < 1`, so the black border around a too-wide simulated lens still receives touches.

- `layoutSubviews` sets `bounds` and `center` rather than `frame`, because `frame` is undefined while a transform is applied.
- `setContentScale(_:animated:)` applies a scale transform, animated over 0.25 s from `updateUIView`.
- `devicePoint(for:)` converts a view point to camera coordinates and clamps to 0…1, so taps in the border map to the nearest edge.

`Coordinator` forwards the recognizers' actions to the closures. `updateUIView` refreshes `coordinator.parent`, so the closures are never stale.

## Example

```swift
CameraPreview(
    session: camera.session,
    contentScale: camera.previewScale,
    onTap: { point, devicePoint in
        focusPoint = point
        camera.focusAndExpose(at: devicePoint, lock: false)
    },
    onLongPress: { point, devicePoint in
        focusPoint = point
        camera.focusAndExpose(at: devicePoint, lock: true)
    },
    onDrag: { deltaY, state in
        camera.setBias(camera.bias - Float(deltaY / 110))
    }
)
```

See [`ContentView`](ContentView.md) and [`CameraController`](CameraController.md).
