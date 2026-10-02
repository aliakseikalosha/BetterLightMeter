import CoreLocation
import Photos
import UIKit

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
}

enum PhotoLibraryError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        String(localized: "Allow access to Photos in Settings to save pictures.")
    }
}

/// Saving photos and managing albums in the user's Photos library.
enum PhotoLibrary {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The user's own albums, sorted by title.
    static func albums() -> [PhotoAlbum] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [PhotoAlbum] = []
        result.enumerateObjects { collection, _, _ in
            if collection.canPerform(.addContent) {
                albums.append(PhotoAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? String(localized: "Untitled")))
            }
        }
        return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func createAlbum(named title: String) async throws -> PhotoAlbum {
        guard await requestAccess() else { throw PhotoLibraryError.accessDenied }
        let identifier = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            identifier.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        return PhotoAlbum(id: identifier.value, title: title)
    }

    /// Saves JPEG data to the library and, if given and still present, to an album.
    static func save(jpeg data: Data, toAlbum albumID: String?, location: CLLocation? = nil) async throws {
        guard await requestAccess() else { throw PhotoLibraryError.accessDenied }
        let album = albumID.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            request.location = location
            if let album,
               let placeholder = request.placeholderForCreatedAsset,
               let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                albumRequest.addAssets([placeholder] as NSArray)
            }
        }
    }

    private final class IdentifierBox: @unchecked Sendable {
        var value = ""
    }
}

/// Tracks the device location so photos can be geotagged.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Asks for permission if needed and starts updating; call when the camera appears.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func stop() { manager.stopUpdatingLocation() }

    /// The latest fix, if recent enough to describe where a photo was taken.
    var currentLocation: CLLocation? {
        guard let location = manager.location, abs(location.timestamp.timeIntervalSinceNow) < 120 else { return nil }
        return location
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Draws the exposure settings onto a photo, like a date stamp.
enum PhotoStamper {
    /// - Parameters:
    ///   - headline: Large first line, e.g. "ISO 400   1/125   f/8".
    ///   - details: Smaller second line, e.g. EV, camera, lens and date.
    static func stamp(_ image: UIImage, headline: String, details: String) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        let short = min(size.width, size.height)
        let margin = short * 0.035
        let headlineFont = UIFont.monospacedDigitSystemFont(ofSize: short * 0.045, weight: .semibold)
        let detailsFont = UIFont.systemFont(ofSize: short * 0.024, weight: .medium)
        let maxTextWidth = size.width - margin * 4

        let headlineText = NSAttributedString(string: headline, attributes: [
            .font: headlineFont,
            .foregroundColor: UIColor.white,
            .kern: short * 0.002,
        ])
        let detailsText = NSAttributedString(string: details, attributes: [
            .font: detailsFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ])
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let headlineBounds = headlineText.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude), options: options, context: nil)
        let detailsBounds = detailsText.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude), options: options, context: nil)

        let spacing = margin * 0.25
        let boxWidth = max(headlineBounds.width, detailsBounds.width) + margin * 2
        let boxHeight = headlineBounds.height + spacing + detailsBounds.height + margin * 1.4
        let box = CGRect(x: margin, y: size.height - margin - boxHeight, width: boxWidth, height: boxHeight)

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))

            UIColor.black.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: margin * 0.4).fill()

            let textX = box.minX + margin
            let headlineY = box.minY + margin * 0.7
            headlineText.draw(with: CGRect(x: textX, y: headlineY, width: maxTextWidth, height: headlineBounds.height), options: options, context: nil)
            detailsText.draw(with: CGRect(x: textX, y: headlineY + headlineBounds.height + spacing, width: maxTextWidth, height: detailsBounds.height), options: options, context: nil)
        }
    }

    /// Stand-in photo for devices without a camera (Simulator).
    static func placeholderPhoto() -> UIImage {
        let size = CGSize(width: 1512, height: 2016)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.darkGray.cgColor, UIColor.gray.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }
}

/// The meter settings in effect when a photo was taken, written into its EXIF data.
struct PhotoMetadata: Sendable {
    var iso: Double
    var shutterSeconds: Double
    var fNumber: Double
    var exposureBias: Double
    var focalLength: Double?
    var camera: String?
    var lens: String?
    var summary: String
    var date: Date = .now

    /// Reads the numbers back from a setting's scale label, e.g. "1/125", `2"`, "f/5.6".
    static func value(of label: String, for setting: ExposureSetting) -> Double {
        var text = label.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "f/", with: "")
        if setting == .shutter, text.hasPrefix("1/"), let denominator = Double(text.dropFirst(2)) {
            return 1 / denominator
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return Double(text) ?? 0
    }

    /// Returns `jpeg` with EXIF/TIFF tags added, keeping pixels and existing metadata untouched.
    func embedded(in jpeg: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let type = CGImageSourceGetType(source) else { return jpeg }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let stamp = formatter.string(from: date)

        var exif: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [Int(iso.rounded())],
            kCGImagePropertyExifExposureTime: shutterSeconds,
            kCGImagePropertyExifFNumber: fNumber,
            kCGImagePropertyExifExposureBiasValue: exposureBias,
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
            kCGImagePropertyExifUserComment: summary,
        ]
        if let focalLength { exif[kCGImagePropertyExifFocalLength] = focalLength }
        if let lens { exif[kCGImagePropertyExifLensModel] = lens }

        var tiff: [CFString: Any] = [kCGImagePropertyTIFFSoftware: "Better Light Meter"]
        if let camera { tiff[kCGImagePropertyTIFFModel] = camera }

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
        ]

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return jpeg }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : jpeg
    }
}
