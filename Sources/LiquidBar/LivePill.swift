import LiquidBarCore
import SwiftUI

/// The one spring every motion in the bar uses.
let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

/// The single open item of one bar. Pills report hover, pulses and their frames here, the dropdown reports the
/// pointer resting in it; `ExpansionInputs` decides the owner, and one timer re-evaluates it when the answer can
/// next change.
@Observable
final class ExpansionSlot {
    private(set) var owner: String?
    /// Pill frames in the bar window, top-left origin, so the dropdown can sit under its item.
    var frames: [String: CGRect] = [:]
    @ObservationIgnored private var inputs = ExpansionInputs<String>()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let created = Date()

    func hover(_ id: String, _ inside: Bool) {
        trace("hover \(id) \(inside ? "in" : "out")")
        let now = Date()
        if inside {
            inputs.inside = .init(id, now)
        } else if inputs.inside?.id == id {
            inputs.inside = nil
            if owner == id { inputs.left = .init(id, now) }
        }
        update()
    }

    func hold(_ inside: Bool) {
        // A dropdown that just closed under the pointer can still report the pointer inside it.
        guard inside != inputs.holding, owner != nil || !inside else { return }
        trace("hold \(inside)")
        inputs.holding = inside
        if !inside, let owner { inputs.left = .init(owner, Date()) }
        update()
    }

    /// Closes the open item now, when one of its rows hands over to a native menu.
    func dismiss() {
        trace("dismiss")
        inputs = ExpansionInputs()
        update()
    }

    func pulse(_ id: String, _ value: String) {
        trace("pulse \(id) \(value)")
        // Sources report their first real state just after launch; that is not news. A change made while the pointer
        // is on the item, like dragging its volume slider, is not news either.
        guard created.timeIntervalSinceNow < -2, inputs.inside?.id != id, !(inputs.holding && owner == id) else { return }
        inputs.pulse = .init(id, Date() + ExpansionInputs<String>.pulseLength)
        update()
    }

    private func update() {
        let (next, recheck) = inputs.owner(now: Date(), current: owner)
        if next != owner {
            trace("owner \(owner ?? "-") -> \(next ?? "-")")
            withAnimation(spring) { owner = next }
        }
        timer?.cancel()
        guard let recheck else { return }
        timer = Task {
            try? await Task.sleep(for: .seconds(recheck.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            update()
        }
    }
}

/// An item that opens when it owns its bar's `ExpansionSlot`: on hover, or by itself for a moment when `pulse`
/// changes. `content` draws the item for the current state.
struct LivePill<Pulse: Equatable, Content: View>: View {
    let id: String
    var pulse: Pulse
    var gap = itemGap
    @ViewBuilder var content: (_ expanded: Bool) -> Content
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        content(slot.owner == id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                slot.frames[id] = $0
                trace("frame \(id) \(Int($0.minX))...\(Int($0.maxX))")
            }
            .barHitArea(gap: gap)
            .onHover { slot.hover(id, $0) }
            .onChange(of: pulse) { slot.pulse(id, "\(pulse)") }
    }
}

/// The space between two items in a bar.
let itemGap: CGFloat = 6

extension EnvironmentValues {
    /// Space between the outermost item of an island and the screen edge, which that item's hit area takes over.
    @Entry var edgeReach = EdgeInsets()
}

extension View {
    /// Stretches an item's hover and click area over the full bar height and half the gap to each neighbour, so a
    /// pointer thrown at the top edge of the screen or between two pills still lands on an item. What is drawn does
    /// not change.
    func barHitArea(gap: CGFloat = itemGap) -> some View {
        modifier(BarHitArea(gap: gap))
    }
}

private struct BarHitArea: ViewModifier {
    let gap: CGFloat
    @Environment(\.edgeReach) private var reach

    func body(content: Content) -> some View {
        // Only the outermost hit area reaches the edge, not the items nested in it, like the workspaces in the strip.
        content
            .environment(\.edgeReach, EdgeInsets())
            .padding(.horizontal, gap / 2)
            .padding(reach)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

/// A glass pill on the right whose menu is the bar's dropdown. It widens a few points while its dropdown is open.
struct MenuPill<Pulse: Equatable, Label: View>: View {
    let id: String
    var pulse: Pulse
    let height: CGFloat
    var padding: CGFloat = 10
    @ViewBuilder var label: () -> Label

    var body: some View {
        LivePill(id: id, pulse: pulse) { open in
            label()
                .fixedSize()
                .padding(.horizontal, open ? 3 : 0)
                .pill(height: height, padding: padding)
        }
    }
}
