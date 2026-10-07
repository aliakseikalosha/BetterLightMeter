import SwiftUI

struct ContentView: View {
    @State private var camera = CameraController()
    @State private var meter = ExposureModel()
    @State private var settings = AppSettings()
    @State private var location = LocationProvider()
    @State private var presets = PresetStore()

    @State private var focusPoint: CGPoint?
    @State private var isDraggingBias = false
    @State private var isIndicatorDimmed = false
    @State private var interactionCount = 0
    @State private var flashOpacity = 0.0
    @State private var isCapturing = false
    @State private var isShowingSettings = false
    @State private var toast: String?
    @State private var lastPhoto: UIImage?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Points of vertical drag per 1 EV of exposure compensation.
    private let pointsPerEV: CGFloat = 110

    /// Width of the column holding the controls when the phone is held sideways.
    private let landscapeControlsWidth: CGFloat = 320

    /// iPhones only get a compact height in landscape.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var selectedCamera: CameraPreset? { presets.camera(named: settings.cameraName) }
    private var selectedLens: LensPreset? { selectedCamera?.lenses.first { $0.name == settings.lensName } }
    private var limits: EffectiveLimits {
        EffectiveLimits(camera: selectedCamera, lens: selectedLens, settings: settings)
    }

    /// 35mm equivalent focal length to show in the viewfinder, if simulating the lens.
    private var simulatedFocalLength: Double? {
        settings.simulateLens ? limits.equivalentFocalLength : nil
    }

    var body: some View {
        // One view tree for both orientations: rotating only moves things, so the camera
        // preview and the wheels are never torn down and rebuilt.
        MeterLayout(isLandscape: isLandscape, controlsWidth: landscapeControlsWidth) {
            topBar
                .padding(.top, isLandscape ? 4 : 0)
            viewfinder
                .padding(.vertical, isLandscape ? 4 : 0)
            controls
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { camera.start(); if settings.saveLocation { location.start() } }
        // The focus square is in viewfinder coordinates, which no longer mean the same place.
        .onChange(of: isLandscape) { focusPoint = nil }
        .onChange(of: settings.saveLocation) { _, isOn in
            if isOn { location.start() } else { location.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
            default: break
            }
        }
        .onChange(of: camera.sceneEV100) { _, ev in
            if let ev { meter.updateScene(ev: ev) }
        }
        .onChange(of: simulatedFocalLength, initial: true) { _, millimeters in
            camera.setEquivalentFocalLength(millimeters)
        }
        .onChange(of: limits.all, initial: true) { _, allowed in
            meter.setAllowed(allowed)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings, presets: presets)
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
        .task(id: interactionCount) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { isIndicatorDimmed = true }
        }
    }

    // MARK: - Sections

    /// Everything under the viewfinder in portrait, or under the top bar beside it in landscape.
    private var controls: some View {
        VStack(spacing: 0) {
            ExposureScale(deviation: meter.deviation)
                .padding(.horizontal, 16)
                .padding(.top, isLandscape ? 4 : 10)
            settingRows
                .padding(.top, 8)
            // Pushes the shutter row to the bottom of the landscape column; has no height in portrait.
            Spacer(minLength: 0)
            bottomBar
        }
    }

    private var settingRows: some View {
        VStack(spacing: 6) {
            ForEach(ExposureSetting.allCases) { setting in
                SettingRow(setting: setting, meter: meter)
            }
        }
        .padding(.horizontal, 12)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SCENE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(format: "EV %.1f", meter.sceneEV))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer()

            if camera.bias != 0 {
                Label(String(format: "%+.1f", camera.bias), systemImage: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
            }

            Spacer()

            if camera.isAEAFLocked {
                badge("AE/AF LOCK")
            } else {
                badge("LIVE", color: .white.opacity(0.25), text: .white)
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: isLandscape ? 40 : 48)
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(
                    session: camera.session,
                    device: camera.device,
                    contentScale: camera.previewScale,
                    onTap: { point, devicePoint in
                        focusPoint = point
                        camera.focusAndExpose(at: devicePoint, lock: false)
                        poke()
                    },
                    onLongPress: { point, devicePoint in
                        focusPoint = point
                        camera.focusAndExpose(at: devicePoint, lock: true)
                        poke()
                    },
                    onDrag: { deltaY, state in
                        handleBiasDrag(deltaY: deltaY, state: state, in: geo.size)
                    }
                )

                placeholder
                    .scaleEffect(camera.previewScale)
                    .animation(.easeOut(duration: 0.25), value: camera.previewScale)
                    .allowsHitTesting(camera.status == .unauthorized)

                if let focusPoint {
                    FocusIndicator(bias: camera.bias, biasLimit: camera.biasLimit, showsTrack: isDraggingBias)
                        .opacity(isIndicatorDimmed && !isDraggingBias ? 0.45 : 1)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }

                cameraReadout
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    gearMenu
                    if let toast {
                        Text(toast)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: Capsule())
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var placeholder: some View {
        switch camera.status {
        case .unavailable:
            ZStack {
                LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                Text("Camera unavailable\nSimulated scene, EV 12")
                    .multilineTextAlignment(.center)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .unauthorized:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("Camera access is needed to meter the scene.")
                    .font(.footnote)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding()
        case .idle, .running:
            EmptyView()
        }
    }

    /// Quick switch between camera and lens presets.
    private var gearMenu: some View {
        Menu {
            if let selectedCamera, !selectedCamera.lenses.isEmpty {
                Section("Lens") {
                    Picker("Lens", selection: $settings.lensName) {
                        ForEach(selectedCamera.lenses) { lens in
                            Text(lens.name).tag(Optional(lens.name))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            Section("Camera") {
                Picker("Camera", selection: Binding(
                    get: { settings.cameraName },
                    set: { settings.selectCamera(presets.camera(named: $0)) }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(presets.cameras) { camera in
                        Text(camera.name).tag(Optional(camera.name))
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "camera.aperture")
                Text([selectedCamera?.name, selectedLens?.name].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                if selectedCamera == nil {
                    Text("No camera preset")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.horizontal, 16)
    }

    /// What the phone camera itself chose, as reference.
    private var cameraReadout: some View {
        VStack(spacing: 4) {
            if let simulatedFocalLength {
                Text("≈ \(Int(simulatedFocalLength.rounded())) mm (35mm equiv.)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            if camera.status == .running, camera.iso > 0 {
                Text("ISO \(Int(camera.iso.rounded()))  ·  \(shutterText(camera.exposureDuration))  ·  f/\(String(format: "%.2g", camera.aperture))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            thumbnailButton
                .frame(width: 48, height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShutterButton(isBusy: isCapturing) {
                takePicture()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing) { _, new in new }

            Button {
                camera.resetMetering()
                withAnimation { focusPoint = nil }
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 20))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .foregroundStyle(.white)
            .opacity(camera.bias != 0 || camera.isAEAFLocked || focusPoint != nil ? 1 : 0.35)
            .accessibilityLabel("Reset metering to center")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, isLandscape ? 6 : 12)
    }

    /// Preview of the last captured photo; opens the Photos app.
    @ViewBuilder
    private var thumbnailButton: some View {
        if let lastPhoto {
            Button {
                if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
            } label: {
                Image(uiImage: lastPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.6), lineWidth: 1))
            }
            .accessibilityLabel("Last photo")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.12))
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions

    private func badge(_ text: LocalizedStringKey, color: Color = .yellow, text textColor: Color = .black) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }

    private func poke() {
        isIndicatorDimmed = false
        interactionCount += 1
    }

    private func handleBiasDrag(deltaY: CGFloat, state: UIGestureRecognizer.State, in size: CGSize) {
        switch state {
        case .began:
            if focusPoint == nil {
                focusPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            }
            isDraggingBias = true
        case .changed:
            break
        default:
            isDraggingBias = false
        }
        camera.setBias(camera.bias - Float(deltaY / pointsPerEV))
        poke()
    }

    private func takePicture() {
        guard !isCapturing else { return }
        isCapturing = true
        flashOpacity = 0.8
        withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }

        // Snapshot the reading at the moment of the press.
        let headline = ExposureSetting.allCases.map { setting in
            setting == .iso ? "ISO \(meter.label(of: setting))" : meter.label(of: setting)
        }.joined(separator: "   ")
        var details = [String(format: "EV %.1f", meter.sceneEV)]
        if abs(meter.deviation) >= 0.05 {
            details.append(String(format: "%+.1f EV", meter.deviation))
        }
        details += [selectedCamera?.name, selectedLens?.name].compactMap { $0 }
        details.append(Date.now.formatted(date: .abbreviated, time: .shortened))
        let detailsLine = details.joined(separator: "  ·  ")
        let metadata = PhotoMetadata(
            iso: PhotoMetadata.value(of: meter.label(of: .iso), for: .iso),
            shutterSeconds: PhotoMetadata.value(of: meter.label(of: .shutter), for: .shutter),
            fNumber: PhotoMetadata.value(of: meter.label(of: .aperture), for: .aperture),
            exposureBias: meter.deviation,
            focalLength: selectedLens?.focalLength,
            camera: selectedCamera?.name,
            lens: selectedLens?.name,
            summary: "\(headline)  ·  \(detailsLine)"
        )
        let albumID = settings.albumID
        let albumTitle = settings.albumTitle
        let photoLocation = settings.saveLocation ? location.currentLocation : nil

        Task {
            defer { isCapturing = false }
            do {
                let photo = try await camera.capturePhoto()
                let jpeg = await Task.detached(priority: .userInitiated) {
                    PhotoStamper.stamp(photo, headline: headline, details: detailsLine).jpegData(compressionQuality: 0.92)
                }.value
                guard let jpeg else { throw CocoaError(.fileWriteUnknown) }
                try await PhotoLibrary.save(jpeg: metadata.embedded(in: jpeg), toAlbum: albumID, location: photoLocation)
                let thumbnail = await Task.detached(priority: .utility) {
                    UIImage(data: jpeg)?.preparingThumbnail(of: CGSize(width: 192, height: 192))
                }.value
                withAnimation { lastPhoto = thumbnail }
                withAnimation { toast = String(localized: "Saved to \(albumTitle ?? String(localized: "Recents"))") }
            } catch {
                withAnimation { toast = String(localized: "Couldn't save: \(error.localizedDescription)") }
            }
        }
    }

    private func shutterText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "–" }
        if seconds >= 0.5 { return String(format: "%.1f\"", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }
}

/// Places three views, in order: top bar, viewfinder, controls.
/// Portrait stacks them vertically. Landscape puts the viewfinder on the left and the top bar
/// above the controls in a column on the right.
private struct MeterLayout: Layout {
    let isLandscape: Bool
    let controlsWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let topBar = subviews[0], viewfinder = subviews[1], controls = subviews[2]

        if isLandscape {
            let columnX = bounds.maxX - controlsWidth
            let topHeight = topBar.sizeThatFits(ProposedViewSize(width: controlsWidth, height: nil)).height
            viewfinder.place(
                at: bounds.origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width - controlsWidth, height: bounds.height)
            )
            topBar.place(
                at: CGPoint(x: columnX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: controlsWidth, height: topHeight)
            )
            controls.place(
                at: CGPoint(x: columnX, y: bounds.minY + topHeight), anchor: .topLeading,
                proposal: ProposedViewSize(width: controlsWidth, height: bounds.height - topHeight)
            )
        } else {
            let widthOnly = ProposedViewSize(width: bounds.width, height: nil)
            let topHeight = topBar.sizeThatFits(widthOnly).height
            let controlsHeight = controls.sizeThatFits(widthOnly).height
            topBar.place(
                at: bounds.origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: topHeight)
            )
            viewfinder.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + topHeight), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: max(0, bounds.height - topHeight - controlsHeight))
            )
            controls.place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY - controlsHeight), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: controlsHeight)
            )
        }
    }
}

#Preview {
    ContentView()
}
