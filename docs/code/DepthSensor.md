# DepthSensor.swift

[← Documentation](../../DOCUMENTATION.md)

Reads the distance to one point from the LiDAR depth delivered with the camera picture.

[`CameraController`](CameraController.md) owns it as `camera.depth` and adds its `output` (an `AVCaptureDepthDataOutput`) to the session while distance is on and the LiDAR camera is in use.

## State

| Property | Meaning |
| --- | --- |
| `distance` | Metres to the measured point, rounded to centimetres; `nil` while there is no reading. `@Observable`, only written on the main thread. |

The point uses the sensor's own orientation, like the camera's device points: (0, 0) is the top left of the picture with the phone in landscape, home side right.

## Control

```swift
camera.depth.measure(at: CGPoint(x: 0.5, y: 0.5))  // device point, the same one the camera meters at
camera.depth.setActive(false)                      // no depth right now: clears the reading
```

`setActive` is called by `CameraController` whenever it knows whether depth can arrive. A frame already in flight is not published once it is off.

## Reading

Depth arrives on a private queue, filtered (holes filled) and at most 10 times a second (`rate`); later frames are skipped. The distance is the median of a 7×7 square of depth pixels around the point, ignoring invalid values, so a stray value at an edge doesn't count.

The point and the active flag, shared between the main thread and the depth queue, are behind an `OSAllocatedUnfairLock`.

## Without a camera

`simulate()` (called when the camera is `.unavailable`, e.g. in the Simulator) makes up a 320×240 scene: a floor going away from the phone (6 m at the top of the upright picture to 0.8 m at the bottom) with a round object 1.8 m away in the middle. While active, it is read with the same code whenever the point changes.
