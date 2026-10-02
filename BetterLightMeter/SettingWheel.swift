import SwiftUI

/// Horizontally scrolling value picker that snaps to the centered value.
/// Shows the scale entries listed in `ids`; `selected` and `onSelect` use scale indices.
struct SettingWheel: View {
    let labels: [String]
    let ids: [Int]
    let selected: Int
    let accent: Color
    let isEnabled: Bool
    let onSelect: (Int) -> Void

    @State private var scrollPosition: ScrollPosition
    /// True between the user touching the wheel and it coming to rest, so programmatic
    /// scrolling (compensation) is never mistaken for user input.
    @State private var isUserScrolling = false
    @State private var feedbackTicks = 0

    private let itemWidth: CGFloat = 76

    init(labels: [String], ids: [Int], selected: Int, accent: Color, isEnabled: Bool, onSelect: @escaping (Int) -> Void) {
        self.labels = labels
        self.ids = ids
        self.selected = selected
        self.accent = accent
        self.isEnabled = isEnabled
        self.onSelect = onSelect
        _scrollPosition = State(initialValue: ScrollPosition(id: selected, anchor: .center))
    }

    /// Scale index of the value currently under the centre marker.
    private var position: Int? {
        scrollPosition.viewID(type: Int.self)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ids, id: \.self) { index in
                        let isSelected = index == selected
                        Text(labels[index])
                            .font(.system(size: isSelected ? 18 : 15, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? accent : .white.opacity(isEnabled ? 0.45 : 0.2))
                            .frame(width: itemWidth, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { if isEnabled { userSelect(index) } }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - itemWidth) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($scrollPosition, anchor: .center)
            .scrollDisabled(!isEnabled)
            // Re-centre once the real width (and so the content margins) is known,
            // and whenever the list of values changes.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _ in
                recenter(animated: false)
            }
            .onChange(of: ids) {
                recenter(animated: false)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting {
                    isUserScrolling = true
                } else if phase == .idle {
                    if isUserScrolling, let position, position != selected {
                        userSelect(position)
                    }
                    isUserScrolling = false
                }
            }
            .onChange(of: position) { _, newValue in
                if isUserScrolling, let newValue, newValue != selected {
                    userSelect(newValue)
                }
            }
            .onChange(of: selected) { _, newValue in
                if !isUserScrolling, position != newValue {
                    recenter(animated: true)
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7))
                .foregroundStyle(accent)
        }
        .sensoryFeedback(.selection, trigger: feedbackTicks)
    }

    private func recenter(animated: Bool) {
        if animated {
            withAnimation(.snappy) { scrollPosition.scrollTo(id: selected, anchor: .center) }
        } else {
            scrollPosition.scrollTo(id: selected, anchor: .center)
        }
    }

    private func userSelect(_ index: Int) {
        feedbackTicks += 1
        onSelect(index)
    }
}
