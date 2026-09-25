import SwiftUI

/// The one spring every motion in the bar uses.
let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

private let hoverIntent = 0.09
private let linger = 0.9
private let pulseLength = 2.2

enum Expansion: Equatable {
    case collapsed, hovered, pulsed(until: Date)
}

/// Expands on hover after a short intent delay, so sweeping the pointer across the bar does not flicker every pill,
/// and by itself for a moment when `pulse` changes. `content` draws the pill for the current state.
struct LivePill<Pulse: Equatable, Content: View>: View {
    var pulse: Pulse
    @ViewBuilder var content: (_ expanded: Bool) -> Content
    @State private var expansion = Expansion.collapsed
    @State private var inside = false
    @State private var pending: Task<Void, Never>?
    @State private var appeared = Date.distantFuture

    var body: some View {
        content(expansion != .collapsed)
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
        .onAppear { appeared = Date() }
        .onChange(of: pulse) {
            // Sources report their first real state just after launch; that is not news.
            guard appeared.timeIntervalSinceNow < -2 else { return }
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

extension LivePill {
    /// The common shape: `compact` always, `detail` sliding in from its trailing edge.
    init<Compact: View, Detail: View>(
        pulse: Pulse,
        @ViewBuilder compact: @escaping () -> Compact,
        @ViewBuilder detail: @escaping () -> Detail
    ) where Content == CompactDetail<Compact, Detail> {
        self.init(pulse: pulse) { CompactDetail(expanded: $0, compact: compact, detail: detail) }
    }
}

struct CompactDetail<Compact: View, Detail: View>: View {
    let expanded: Bool
    let compact: () -> Compact
    let detail: () -> Detail

    var body: some View {
        HStack(spacing: 8) {
            compact()
            if expanded {
                detail().transition(.blurReplace.combined(with: .scale(0.7, anchor: .leading)))
            }
        }
    }
}
