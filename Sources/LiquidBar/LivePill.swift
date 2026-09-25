import LiquidBarCore
import SwiftUI

/// The one spring every motion in the bar uses.
let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

/// The single expanded pill of one bar. Pills report hover and pulses here; `ExpansionInputs` decides the owner,
/// and one timer re-evaluates it when the answer can next change.
@Observable
final class ExpansionSlot {
    private(set) var owner: String?
    @ObservationIgnored private var inputs = ExpansionInputs<String>()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let created = Date()

    func hover(_ id: String, _ inside: Bool) {
        let now = Date()
        if inside {
            inputs.inside = .init(id, now)
        } else if inputs.inside?.id == id {
            inputs.inside = nil
            if owner == id { inputs.left = .init(id, now) }
        }
        update()
    }

    func pulse(_ id: String) {
        // Sources report their first real state just after launch; that is not news.
        guard created.timeIntervalSinceNow < -2 else { return }
        inputs.pulse = .init(id, Date() + ExpansionInputs<String>.pulseLength)
        update()
    }

    private func update() {
        let (next, recheck) = inputs.owner(now: Date(), current: owner)
        if next != owner { withAnimation(spring) { owner = next } }
        timer?.cancel()
        guard let recheck else { return }
        timer = Task {
            try? await Task.sleep(for: .seconds(recheck.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            update()
        }
    }
}

/// A pill that expands when it owns its bar's `ExpansionSlot`: on hover, or by itself for a moment when `pulse`
/// changes. `content` draws the pill for the current state.
struct LivePill<Pulse: Equatable, Content: View>: View {
    let id: String
    var pulse: Pulse
    @ViewBuilder var content: (_ expanded: Bool) -> Content
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        content(slot.owner == id)
            .contentShape(Rectangle())
            .fluidItem(id)
            .onHover { slot.hover(id, $0) }
            .onChange(of: pulse) { slot.pulse(id) }
    }
}

extension LivePill {
    /// The common shape: `compact` always, `detail` sliding in from its trailing edge.
    init<Compact: View, Detail: View>(
        id: String,
        pulse: Pulse,
        @ViewBuilder compact: @escaping () -> Compact,
        @ViewBuilder detail: @escaping () -> Detail
    ) where Content == CompactDetail<Compact, Detail> {
        self.init(id: id, pulse: pulse) { CompactDetail(expanded: $0, compact: compact, detail: detail) }
    }
}

/// The detail yields when the island has no room for it, so an expanded pill never pushes its island past the
/// notch or the screen edge.
struct CompactDetail<Compact: View, Detail: View>: View {
    let expanded: Bool
    let compact: () -> Compact
    let detail: () -> Detail

    var body: some View {
        HStack(spacing: 8) {
            compact().fixedSize()
            if expanded {
                ViewThatFits(in: .horizontal) {
                    detail().fixedSize()
                    Color.clear.frame(width: 0)
                }
                .transition(.blurReplace.combined(with: .scale(0.7, anchor: .leading)))
            }
        }
    }
}
