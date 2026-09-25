import SwiftUI

/// The one spring every motion in the bar uses.
let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

private let hoverIntent = 0.09
private let linger = 0.9
private let pulseLength = 2.2

enum Expansion: Equatable {
    case collapsed, hovered, pulsed(until: Date)
}

/// Shows `compact` at rest and slides `detail` in beside it. Hover expands after a short intent delay, so sweeping
/// the pointer across the bar does not flicker every pill; a change of `pulse` expands it by itself for a moment.
struct LivePill<Pulse: Equatable, Compact: View, Detail: View>: View {
    var pulse: Pulse
    var pinned = false
    var spacing: CGFloat = 8
    @ViewBuilder var compact: () -> Compact
    @ViewBuilder var detail: () -> Detail
    @State private var expansion = Expansion.collapsed
    @State private var inside = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        HStack(spacing: spacing) {
            compact()
            if pinned || expansion != .collapsed {
                detail()
                    .transition(.blurReplace.combined(with: .scale(0.7, anchor: .leading)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            inside = hovering
            if hovering {
                expansion == .hovered ? pending?.cancel() : set(.hovered, after: hoverIntent)
            } else {
                switch expansion {
                case .collapsed: pending?.cancel()
                case .hovered: set(.collapsed, after: linger)
                case .pulsed(let until): set(.collapsed, after: max(until.timeIntervalSinceNow, linger))
                }
            }
        }
        .onChange(of: pulse) {
            if inside {
                set(.hovered, after: 0)
            } else {
                withAnimation(spring) { expansion = .pulsed(until: Date().addingTimeInterval(pulseLength)) }
                set(.collapsed, after: pulseLength)
            }
        }
    }

    private func set(_ next: Expansion, after delay: Double) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, expansion != next else { return }
            withAnimation(spring) { expansion = next }
        }
    }
}
