# PhotoLibrary.swift

[← Documentation](../../DOCUMENTATION.md)

Everything about getting a photo out of the app: stamping the reading onto the image, writing EXIF, saving to Photos, and geotagging.

## PhotoLibrary

Namespace (`enum`) for Photos access.

```swift
let granted = await PhotoLibrary.requestAccess()   // read/write; .limited counts as granted

let albums = PhotoLibrary.albums()                  // user albums that accept content, sorted by title
let album = try await PhotoLibrary.createAlbum(named: "Light Meter")

try await PhotoLibrary.save(jpeg: data, toAlbum: album.id, location: location)
```

- `save` always adds the photo to the library and, if the album still exists, to the album too. A missing album is skipped silently.
- Both `save` and `createAlbum` throw `PhotoLibraryError.accessDenied` without permission.
- `IdentifierBox` carries the new album's identifier out of the `performChanges` closure.

## LocationProvider

A `@MainActor` `CLLocationManager` wrapper (accuracy: nearest ten metres).

```swift
location.start()                 // request when-in-use permission, or start updating
location.stop()
location.currentLocation         // latest fix, or nil if older than 120 s
```

When the permission changes to authorised, the delegate starts updates. `ContentView` starts and stops it according to `AppSettings.saveLocation`.

## PhotoStamper

Draws the exposure onto a photo, like a date stamp, in the bottom-left corner on a translucent rounded box. All sizes scale with the image's short side, so the stamp looks the same on any resolution.

```swift
let stamped = PhotoStamper.stamp(
    photo,
    headline: "ISO 400   1/125   f/8",
    details: "EV 12.3  ·  Leica M6  ·  Summicron 35mm"
)
```

`placeholderPhoto()` returns a grey gradient used when there is no camera (Simulator).

## PhotoMetadata

The values written to the JPEG's EXIF/TIFF tags: ISO, exposure time, f-number, exposure bias (the deviation), focal length, camera as TIFF model, lens as lens model, date, and a summary in the user comment. `Software` is set to "Better Light Meter".

```swift
let metadata = PhotoMetadata(
    iso: PhotoMetadata.value(of: "400", for: .iso),            // 400
    shutterSeconds: PhotoMetadata.value(of: "1/125", for: .shutter), // 0.008
    fNumber: PhotoMetadata.value(of: "f/5.6", for: .aperture), // 5.6
    exposureBias: 0,
    summary: "ISO 400   1/125   f/5.6"
)
let tagged = metadata.embedded(in: jpegData)
```

`value(of:for:)` parses a scale label back to a number (`"1/125"`, `2"`, `"f/5.6"`). `embedded(in:)` re-encodes through `CGImageDestination` copying the image from its source, so pixels and existing metadata stay untouched. On any failure it returns the original data.

See `ContentView.takePicture()` for the full pipeline: capture → stamp → embed → save.
