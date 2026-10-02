import SwiftUI

/// Yellow focus square with the exposure-compensation sun next to it, like the Camera app.
struct FocusIndicator: View {
    let bias: Float
    let biasLimit: Float
    let showsTrack: Bool

    static let squareSize: CGFloat = 76
    private let trackHeight: CGFloat = 130
    private let sunWidth: CGFloat = 26
    private let spacing: CGFloat = 6

    /// Offset that keeps the square (not the whole indicator) centered on the tapped point.
    var centeringOffset: CGFloat { (spacing + sunWidth) / 2 }

    var body: some View {
        HStack(spacing: spacing) {
            Rectangle()
                .stroke(Color.yellow, lineWidth: 1.2)
                .frame(width: Self.squareSize, height: Self.squareSize)

            ZStack {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1, height: trackHeight)
                    .opacity(showsTrack ? 1 : 0)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.yellow)
                    .offset(y: -CGFloat(bias / biasLimit) * trackHeight / 2)
            }
            .frame(width: sunWidth, height: trackHeight)
        }
        .offset(x: centeringOffset)
    }
}

/// -3…+3 EV scale showing how far the chosen settings are from the metered exposure.
struct ExposureScale: View {
    /// Positive = overexposed.
    let deviation: Double

    private let range = 3.0

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let inset: CGFloat = 12
                let usable = size.width - inset * 2
                func x(_ ev: Double) -> CGFloat { inset + CGFloat((ev + range) / (range * 2)) * usable }

                for step in -9...9 {
                    let ev = Double(step) / 3
                    let isMajor = step % 3 == 0
                    var tick = Path()
                    tick.move(to: CGPoint(x: x(ev), y: size.height - (isMajor ? 10 : 5)))
                    tick.addLine(to: CGPoint(x: x(ev), y: size.height))
                    context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.8 : 0.4)), lineWidth: 1)

                    if isMajor {
                        let label = step == 0 ? "0" : String(format: "%+d", step / 3)
                        context.draw(
                            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6)),
                            at: CGPoint(x: x(ev), y: size.height - 18)
                        )
                    }
                }

                let clamped = min(max(deviation, -range), range)
                let needleX = x(clamped)
                var needle = Path()
                needle.move(to: CGPoint(x: needleX - 5, y: size.height + 1))
                needle.addLine(to: CGPoint(x: needleX + 5, y: size.height + 1))
                needle.addLine(to: CGPoint(x: needleX, y: size.height - 9))
                needle.closeSubpath()
                context.fill(needle, with: .color(abs(deviation) > range ? .red : .yellow))
            }
            .frame(height: 30)

            Text(deviationText)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(abs(deviation) > 1.0 / 3 ? .yellow : .white.opacity(0.6))
        }
    }

    private var deviationText: String {
        if abs(deviation) < 0.05 { return String(localized: "Correct exposure") }
        let amount = String(format: "%.1f EV", abs(deviation))
        return deviation > 0 ? String(localized: "Overexposed by \(amount)") : String(localized: "Underexposed by \(amount)")
    }
}

/// One row: lock toggle on the left, value wheel on the right.
struct SettingRow: View {
    let setting: ExposureSetting
    let meter: ExposureModel

    @State private var resetTicks = 0

    var body: some View {
        let isLocked = meter.isLocked(setting)
        let isAuto = meter.adjusting == setting
        let isManual = meter.adjusting == nil && !isLocked

        HStack(spacing: 4) {
            Button {
                meter.toggleLock(setting)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 15, weight: .semibold))
                    Text(setting.title)
                        .font(.system(size: 9, weight: .bold))
                    Group {
                        if meter.isFixed(setting) { Text("FIXED") }
                        else if isLocked { Text("LOCKED") }
                        else if isAuto { Text("AUTO") }
                        else if isManual { Text("MANUAL") }
                        else { Text(verbatim: " ") }
                    }
                        .font(.system(size: 8, weight: .semibold))
                        .opacity(0.8)
                }
                .foregroundStyle(isLocked ? Color.yellow : .white.opacity(0.6))
                .frame(width: 70, height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: isLocked)

            SettingWheel(
                labels: setting.scale.labels,
                ids: meter.allowedIndices(for: setting),
                selected: meter.index(of: setting),
                accent: isAuto ? .yellow : .white,
                isEnabled: meter.isEditable(setting),
                isDimmed: isLocked,
                onSelect: { meter.select($0, for: setting) },
                onDoubleTap: {
                    if meter.canResetToAuto(setting) {
                        meter.resetToAuto(setting)
                        resetTicks += 1
                    }
                }
            )
        }
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(isLocked ? 0.1 : 0.05))
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: resetTicks)
    }
}

/// Camera-app style shutter button.
struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 63, height: 63)
                    .opacity(isBusy ? 0.5 : 1)
                if isBusy {
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .buttonStyle(ShutterPressStyle())
        .disabled(isBusy)
        .accessibilityLabel("Take picture")
    }
}

private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
