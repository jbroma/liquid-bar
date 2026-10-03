import AppKit
import LiquidBarCore
import SwiftUI

/// The spring most motions in the bar use.
let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

/// The single open item of one bar. Pills report hover, pulses and their frames here, the dropdown reports the
/// pointer resting in it; `ExpansionInputs` decides the owner, and one timer re-evaluates it when the answer can
/// next change.
@Observable
final class ExpansionSlot {
    private(set) var owner: Dropdown?
    /// The pill showing its change inline, widened, instead of opening its dropdown.
    private(set) var inline: Dropdown?
    /// Pill frames in the bar window, top-left origin, so the dropdown can sit under its item.
    var frames: [Dropdown: CGRect] = [:]
    /// The pill hit areas, and each side's open dropdown from the bar's bottom, in the same coordinates.
    @ObservationIgnored var hits: [Dropdown: CGRect] = [:]
    @ObservationIgnored var dropdowns: [Bool: CGRect] = [:]
    @ObservationIgnored private var inputs = ExpansionInputs<Dropdown>(quietUntil: Date() + 2)
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The bar's screen; only the screen the user is looking at, the pointer's, pulses.
    @ObservationIgnored private let screen: CGRect
    @ObservationIgnored private var wake: NSObjectProtocol?
    /// Esc closes the open item; the monitor exists only while one is open.
    @ObservationIgnored private var escape: Any?
    /// SwiftUI can miss a hover exit, so while an item is open the real pointer is checked against its areas.
    @ObservationIgnored private var watch: Task<Void, Never>?

    init(screen: CGRect) {
        self.screen = screen
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputs.woke(at: Date()) }
        }
    }

    isolated deinit {
        wake.map(NSWorkspace.shared.notificationCenter.removeObserver)
        escape.map(NSEvent.removeMonitor)
        watch?.cancel()
    }

    func hover(_ id: Dropdown, _ inside: Bool) {
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

    private func checkPointer() {
        guard let owner else { return }
        let pointer = NSEvent.mouseLocation
        let point = CGPoint(x: pointer.x - screen.minX, y: screen.maxY - pointer.y)
        let overPill = inputs.inside.flatMap { hits[$0.id] }?.contains(point) ?? false
        let overDropdown = dropdowns[owner.isLeft]?.contains(point) ?? false
        if inputs.pointer(overPill: overPill, overDropdown: overDropdown, now: Date(), current: owner) {
            trace("pointer check pill=\(overPill) dropdown=\(overDropdown)")
            update()
        }
    }

    /// Closes the open item now, when one of its rows hands over to a native menu.
    func dismiss() {
        trace("dismiss")
        inputs = ExpansionInputs(quietUntil: inputs.quietUntil)
        update()
    }

    func pulse(_ id: Dropdown, _ value: String) {
        trace("pulse \(id) \(value)")
        // NSMouseInRect counts the top edge as inside, where the pointer rests when pushed against the menu bar.
        guard NSMouseInRect(NSEvent.mouseLocation, screen, false) else { return }
        if inputs.startPulse(id, now: Date(), current: owner) { update() }
    }

    func showInline(_ id: Dropdown, _ value: String) {
        trace("inline \(id) \(value)")
        guard NSMouseInRect(NSEvent.mouseLocation, screen, false) else { return }
        if inputs.startInline(id, now: Date(), current: owner) { update() }
    }

    private func update() {
        let now = Date()
        let (next, ownerRecheck) = inputs.owner(now: now, current: owner)
        let (nextInline, inlineRecheck) = inputs.inlined(now: now, current: next)
        let recheck = [ownerRecheck, inlineRecheck].compactMap { $0 }.min()
        if nextInline != inline { withAnimation(spring) { inline = nextInline } }
        if next != owner {
            trace("owner \(owner.map { "\($0)" } ?? "-") -> \(next.map { "\($0)" } ?? "-")")
            // A short spring: the bar redraws on every frame of it, and the longer one cost twice the CPU.
            withAnimation(.spring(duration: 0.22, bounce: 0.2)) { owner = next }
            if next == nil {
                escape.map(NSEvent.removeMonitor)
                escape = nil
                watch?.cancel()
                watch = nil
            } else if escape == nil {
                watch = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(40))
                        checkPointer()
                    }
                }
                escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53 else { return }
                    MainActor.assumeIsolated { self?.dismiss() }
                }
            }
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
    let id: Dropdown
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { slot.hits[id] = $0 }
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

/// A pill on the right that opens something of macOS's own on a click rather than a dropdown. It widens a few points
/// under the pointer.
struct ClickPill<Label: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var label: () -> Label
    @Environment(\.bar) private var bar
    @State private var hovering = false

    var body: some View {
        label()
            .fixedSize()
            .pill(height: bar.pill, padding: padding, lit: hovering)
            .barHitArea()
            .onHover { hovering = $0 }
    }
}

/// A pill on the right whose menu is the bar's dropdown. It widens a few points while its dropdown is open.
struct MenuPill<Pulse: Equatable, Label: View>: View {
    let id: Dropdown
    var pulse: Pulse
    var padding: CGFloat = 10
    @ViewBuilder var label: () -> Label
    @Environment(\.bar) private var bar

    var body: some View {
        LivePill(id: id, pulse: pulse) { open in
            label()
                .fixedSize()
                .pill(height: bar.pill, padding: padding, lit: open)
        }
    }
}
