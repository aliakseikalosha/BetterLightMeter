# MeterViews.swift

[← Documentation](../../DOCUMENTATION.md)

Small SwiftUI views used by [`ContentView`](ContentView.md).

## FocusIndicator

The yellow focus square with the exposure-compensation sun next to it.

| Parameter | Meaning |
| --- | --- |
| `bias`, `biasLimit` | The sun is offset vertically by `-bias / biasLimit * trackHeight / 2`. |
| `showsTrack` | Shows the vertical track while the user drags. |

The whole view is offset by `centeringOffset`, so the *square*, not the square plus sun, is centred on the tapped point.

```swift
FocusIndicator(bias: camera.bias, biasLimit: camera.biasLimit, showsTrack: isDraggingBias)
    .position(focusPoint)
```

## ExposureScale

A −3…+3 EV scale drawn with `Canvas`. Ticks every 1/3 EV (major each whole EV with a label); a needle shows `deviation` (positive = overexposed). Beyond ±3 the needle is clamped to the end and turns red. The text below reads "Correct exposure" within 0.05 EV, otherwise "Overexposed/Underexposed by x.x EV", highlighted when over 1/3 EV off.

```swift
ExposureScale(deviation: meter.deviation)
```

## SettingRow

One row per `ExposureSetting`: a lock button on the left and a [`SettingWheel`](SettingWheel.md) on the right.

The caption under the setting name is derived from the [`ExposureModel`](ExposureModel.md):

| Caption | Condition |
| --- | --- |
| FIXED | only one allowed value |
| LOCKED | the setting is locked |
| AUTO | it is the setting being compensated (wheel accent is yellow) |
| MANUAL | not locked and nothing compensates |

Double tapping the wheel calls `meter.resetToAuto` when `canResetToAuto` is true, with a haptic.

```swift
ForEach(ExposureSetting.allCases) { setting in
    SettingRow(setting: setting, meter: meter)
}
```

## ShutterButton

Camera-style round button. While `isBusy` it is dimmed, disabled and shows a `ProgressView`. `ShutterPressStyle` shrinks it to 0.9 while pressed.

```swift
ShutterButton(isBusy: isCapturing) { takePicture() }
```
