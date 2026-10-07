# ExposureModel.swift

[← Documentation](../../DOCUMENTATION.md)

The exposure maths and the logic that keeps ISO, shutter and aperture matched to the metered scene.

## Stops

Every setting is converted to "stops", so the exposure equation becomes a sum:

```
aperture  a = log2(N²)        (f/1   = 0)
shutter   s = log2(1 / t)     (1"    = 0)
ISO       i = log2(ISO / 100) (ISO 100 = 0)

EV100 = a + s − i
```

### `StopScale`

A list of display `labels` in 1/3-stop steps, plus the stops value of the first label (`firstStop`).

```swift
let scale = ExposureSetting.shutter.scale
scale.stops(at: 36)           // firstStop + 36/3
scale.nearestIndex(toStops: -7.2)
```

### `ExposureSetting`

`enum` with `.iso`, `.shutter`, `.aperture`. It provides titles (localized), the `scale`, and `evSign` (−1 for ISO, +1 otherwise). Helpers:

```swift
ExposureSetting.aperture.nearestIndex(forValue: 2.8)  // index of "f/2.8"
ExposureSetting.shutter.stops(forValue: 1.0 / 125)
ExposureSetting.iso.allIndices                         // 0..<31
```

## ExposureModel

An `@Observable` class that holds the current `indices` (one per setting) and the metered `sceneEV`. It remembers its state between launches (see [Remembering the state](#remembering-the-state)).

### Locking and compensation

- Up to `maxLocks` (2) settings can be locked. A locked setting never changes by itself. Locking a third releases the oldest lock.
- Otherwise one unlocked setting is the **auto candidate**: the least recently touched one. Never-touched settings go first, in the order shutter → aperture → ISO. It is recomputed on every change to compensate for the scene.
- The user can still set any setting by hand. If they change the only unlocked setting, it becomes `manualOverride`; nothing compensates (`adjusting == nil`) until `resetToAuto`.

`compensate()` solves for the candidate:

```
needed = (sceneEV − Σ others) × target.evSign
indices[target] = nearestAllowed(for: target, toStops: needed)
```

### API

```swift
let meter = ExposureModel()

meter.updateScene(ev: 13.2)          // ignored if held or the change is < 0.1 EV
meter.select(24, for: .aperture)     // user picked a value
meter.toggleLock(.iso)               // lock / unlock
meter.resetToAuto(.shutter)          // make it the compensating setting again

meter.deviation                      // sceneEV − settingsEV; positive = overexposed
meter.adjusting                      // which setting is currently automatic
meter.label(of: .shutter)            // "1/125"
```

Preset limits come in through `setAllowed(_:)` (fed by `EffectiveLimits.all`, see [AppSettings](AppSettings.md)). Current values are moved to the nearest allowed value, then `compensate()` runs. A setting with a single allowed value is *fixed* and not editable. `select` rejects indices that are not allowed.

`setHeld(_:currentEV:)` freezes live readings; releasing applies the latest one.

### Remembering the state

The model saves itself to `UserDefaults` (key `exposureState`, JSON) and restores on the next launch, so the wheels and locks come back as they were left. `init(defaults:)` takes the store, which defaults to `.standard`.

What is saved: the three `indices`, `locks`, `touchOrder` and `manualOverride` (so the same wheel stays automatic and a hand-set one stays manual), and the last `sceneEV` (so the deviation scale reads as before until the first live reading arrives).

- Every change to the state ends in `compensate()`, which calls `save()`. It only writes when something other than `sceneEV` changed; the light alone would mean a write every time the camera moves, so it is stored along with the next real change.
- `restore()` tolerates stale or damaged data: indices are clamped to their scale, locks are de-duplicated and cut to `maxLocks`, and a `manualOverride` on a locked setting is dropped. Data that does not decode is ignored and the defaults are used.
- After a restore, `setAllowed(_:)` still moves values into the range of the selected camera and lens, so a remembered value never escapes the presets.

## Example: metering sequence

With ISO 100 (fixed), aperture locked at f/8 and a scene of EV 13: shutter is the auto candidate, so `compensate()` picks the index nearest to `s = 13 + 0 − 6 = 7` stops, i.e. 1/125.
