# SettingWheel.swift

[← Documentation](../../DOCUMENTATION.md)

A horizontally scrolling value picker that snaps to the centred value. Each of ISO, shutter and aperture uses one in [`SettingRow`](MeterViews.md).

## Parameters

| Parameter | Meaning |
| --- | --- |
| `labels` | All labels of the scale. |
| `ids` | Scale indices that are shown (the allowed values). |
| `selected` | Selected scale index. |
| `accent` | Colour of the selected value and the marker (yellow when automatic). |
| `isEnabled` | `false` disables scrolling and tapping. |
| `isDimmed` | Fades unselected values, e.g. when locked. |
| `onSelect` | Called with the new scale index. |
| `onDoubleTap` | Called on double tap (reset to auto). |

`selected` and `onSelect` use scale indices, not positions in `ids`, so the wheel keeps working when the allowed list changes.

## How it works

- A `ScrollView` with `.scrollTargetBehavior(.viewAligned)` and content margins of half the width minus half an item, so any item can sit in the centre. A `ScrollPosition` anchored at `.center` tracks the item under the marker.
- **User vs. programmatic scrolling.** The model changes the selected value by itself (compensation). `isUserScrolling` is true from touch-down until the wheel is idle, so those changes aren't treated as input. While the user scrolls, a new centred item is passed to `onSelect`; when scrolling ends, the final one is committed.
- When `selected` changes while the user isn't scrolling, the wheel re-centres with a `.snappy` animation. It also re-centres, without animation, when the width becomes known or when `ids` changes.
- Tap selects the tapped value; the double-tap gesture is declared first so a double tap doesn't also select.
- Edges fade out with a gradient mask, and `.sensoryFeedback(.selection)` ticks on each user selection.

## Example

```swift
SettingWheel(
    labels: ExposureSetting.shutter.scale.labels,
    ids: meter.allowedIndices(for: .shutter),
    selected: meter.index(of: .shutter),
    accent: .yellow,
    isEnabled: true,
    isDimmed: false,
    onSelect: { meter.select($0, for: .shutter) },
    onDoubleTap: { meter.resetToAuto(.shutter) }
)
.frame(height: 50)
```
