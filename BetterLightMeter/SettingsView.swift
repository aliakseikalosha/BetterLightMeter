import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let presets: PresetStore

    @Environment(\.dismiss) private var dismiss

    @State private var albums: [PhotoAlbum] = []
    @State private var photoAccessDenied = false
    @State private var isNamingAlbum = false
    @State private var newAlbumName = ""
    @State private var isImporting = false
    @State private var isConfirmingReset = false
    @State private var copiedFormat = false
    @State private var message: (title: String, body: String)?

    private var camera: CameraPreset? { presets.camera(named: settings.cameraName) }
    private var lens: LensPreset? { camera?.lenses.first { $0.name == settings.lensName } }
    private var limits: EffectiveLimits { EffectiveLimits(camera: camera, lens: lens, settings: settings) }

    var body: some View {
        NavigationStack {
            Form {
                gearSection
                limitsSection
                saveSection
                presetsSection
                languageSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadAlbums() }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importPresets(result)
            }
            .alert("New Album", isPresented: $isNamingAlbum) {
                TextField("Album name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { Task { await createAlbum() } }
            }
            .alert("Reset presets?", isPresented: $isConfirmingReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    presets.resetToBuiltIn()
                    if camera == nil { settings.cameraName = nil; settings.lensName = nil }
                }
            } message: {
                Text("Imported cameras will be removed and the built-in presets restored.")
            }
            .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message?.body ?? "")
            }
        }
    }

    // MARK: - Sections

    private var gearSection: some View {
        Section {
            Picker("Camera", selection: Binding(
                get: { settings.cameraName },
                set: { settings.selectCamera(presets.camera(named: $0)) }
            )) {
                Text("None").tag(String?.none)
                ForEach(presets.cameras) { camera in
                    Text(camera.name).tag(Optional(camera.name))
                }
            }

            if let camera, !camera.lenses.isEmpty {
                Picker("Lens", selection: $settings.lensName) {
                    Text("None").tag(String?.none)
                    ForEach(camera.lenses) { lens in
                        Text(lens.name).tag(Optional(lens.name))
                    }
                }
                // A fixed-lens camera has nothing to choose.
                .disabled(camera.lenses.count == 1)
            }

            ForEach(ExposureSetting.allCases) { setting in
                LabeledContent(setting.displayName) {
                    Text(limits.describe(setting))
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Camera & Lens")
        } footer: {
            Text(lens?.shutter != nil ? "This lens has its own leaf shutter, which sets the shutter speed range." :
                    "The camera sets the ISO and shutter speed range, the lens sets the aperture range.")
        }
    }

    private var limitsSection: some View {
        Section {
            ForEach(ExposureSetting.allCases) { setting in
                limitRow(for: setting)
            }
            Button("Remove Limits") { settings.resetLimits() }
        } header: {
            Text("Limits")
        } footer: {
            Text("Your own limits, applied on top of the camera and lens.")
        }
    }

    private func limitRow(for setting: ExposureSetting) -> some View {
        let range = settings.limit(for: setting)
        let labels = setting.scale.labels
        let titles = setting.limitTitles

        return VStack(alignment: .leading, spacing: 4) {
            Text(setting.displayName)
                .font(.subheadline.weight(.semibold))
            HStack {
                Picker(titles.low, selection: Binding(
                    get: { range.lowerBound },
                    set: { settings.setLimit(low: $0, high: max($0, range.upperBound), for: setting) }
                )) {
                    ForEach(setting.allIndices, id: \.self) { Text(labels[$0]).tag($0) }
                }
                Spacer()
                Picker(titles.high, selection: Binding(
                    get: { range.upperBound },
                    set: { settings.setLimit(low: min($0, range.lowerBound), high: $0, for: setting) }
                )) {
                    ForEach(setting.allIndices, id: \.self) { Text(labels[$0]).tag($0) }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .overlay {
                Text("to").foregroundStyle(.secondary)
            }

            if limits.userLimitConflicts(for: setting) {
                Label(lens != nil && setting != .iso ? "Outside the lens range, so it is ignored." : "Outside the camera range, so it is ignored.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Picker("Save to", selection: Binding(
                get: { settings.albumID },
                set: { id in
                    settings.albumID = id
                    settings.albumTitle = albums.first { $0.id == id }?.title
                }
            )) {
                Text("Recents only").tag(String?.none)
                ForEach(albums) { album in
                    Text(album.title).tag(Optional(album.id))
                }
                // Keep a remembered album selectable even before the list has loaded.
                if let id = settings.albumID, !albums.contains(where: { $0.id == id }) {
                    Text(settings.albumTitle ?? String(localized: "Album")).tag(Optional(id))
                }
            }

            Button("New Album…") {
                newAlbumName = String(localized: "Light Meter")
                isNamingAlbum = true
            }

            Toggle("Save Location", isOn: $settings.saveLocation)
        } header: {
            Text("Photos")
        } footer: {
            if photoAccessDenied {
                Text("Allow full access to Photos in the Settings app to choose an album.")
            } else {
                Text("The shutter button takes a picture with the meter settings printed on it.")
                    + Text(" ")
                    + Text("Save Location tags pictures with where they were taken, if you allow location access.")
            }
        }
    }

    private var presetsSection: some View {
        Section {
            Button("Import Presets from JSON…") { isImporting = true }
            Button("Reset to Built-in Presets", role: .destructive) { isConfirmingReset = true }
            DisclosureGroup("JSON Format") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.formatExample)
                        .font(.system(size: 11, design: .monospaced))
                    Label(copiedFormat ? "Copied" : "Tap to copy", systemImage: copiedFormat ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { copyFormatExample() }
                .sensoryFeedback(.success, trigger: copiedFormat) { _, copied in copied }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Cameras with the same name are replaced. Values can be numbers or text such as \"1/500\", \"2s\" or \"f/2.8\". A single value fixes a setting, e.g. \"iso\": 400.")
        }
    }

    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(Self.currentLanguageName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("The app uses your iPhone's language if it's supported, otherwise English. To change it, choose Language on the app's page in the Settings app.")
        }
    }

    /// Name of the language the app is shown in, written in that language.
    private static var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }

    // MARK: - Actions

    private func loadAlbums() async {
        guard await PhotoLibrary.requestAccess() else {
            photoAccessDenied = true
            return
        }
        albums = PhotoLibrary.albums()
        if let id = settings.albumID, let album = albums.first(where: { $0.id == id }) {
            settings.albumTitle = album.title
        }
    }

    private func createAlbum() async {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let album = try await PhotoLibrary.createAlbum(named: name)
            albums = PhotoLibrary.albums()
            settings.albumID = album.id
            settings.albumTitle = album.title
        } catch {
            message = (String(localized: "Couldn't Create Album"), error.localizedDescription)
        }
    }

    private func copyFormatExample() {
        UIPasteboard.general.string = Self.formatExample
        copiedFormat = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedFormat = false
        }
    }

    private func importPresets(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let count = try presets.importPresets(from: Data(contentsOf: url))
            message = (String(localized: "Presets Imported"), String(localized: "\(count) cameras imported."))
        } catch {
            message = (String(localized: "Couldn't Import Presets"), describe(error))
        }
    }

    private static let formatExample = """
    {
      "cameras": [
        {
          "name": "Leica M6",
          "shutter": { "min": "1", "max": "1/1000", "fullStops": true },
          "lenses": [
            { "name": "Summicron 35mm f/2",
              "aperture": { "min": 2, "max": 16 } }
          ]
        },
        {
          "name": "Hasselblad 500C/M",
          "iso": 400,
          "lenses": [
            { "name": "Planar 80mm f/2.8",
              "aperture": { "min": 2.8, "max": 22 },
              "shutter": { "min": "1", "max": "1/500",
                           "fullStops": true } }
          ]
        }
      ]
    }
    """
}
