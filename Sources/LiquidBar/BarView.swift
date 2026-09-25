import LiquidBarCore
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }

    static let barWhite = Color(hex: 0xf7f1ff)
    static let barGreen = Color(hex: 0x7bd88f)
    static let barYellow = Color(hex: 0xfce566)
    static let barRed = Color(hex: 0xfc618d)
}

let spring = Animation.spring(response: 0.35, dampingFraction: 0.72)

/// One bar per screen. `leftWidth`/`rightWidth` are the areas beside the notch; nil means no notch.
struct BarView: View {
    let model: BarModel
    let screenFrame: CGRect
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?

    var body: some View {
        let config = model.config
        let island = config.height - 6
        HStack(spacing: 0) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(Array(config.left.enumerated()), id: \.offset) { _, widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, itemHeight: island - 6)
                    }
                }
                .padding(3)
                .frame(height: island)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.leading, config.margin)
            .frame(width: leftWidth, alignment: .leading)

            Spacer(minLength: 0)

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(Array(config.right.enumerated()), id: \.offset) { _, widget in
                        Group {
                            if widget == .volume {
                                VolumeItem(model: model, height: island)
                            } else {
                                WidgetView(model: model, widget: widget, screenFrame: screenFrame, itemHeight: island)
                                    .pill(height: island)
                            }
                        }
                        .onTapGesture { model.click(widget) }
                    }
                }
            }
            .padding(.trailing, config.margin)
            .frame(width: rightWidth, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    func pill(height: CGFloat) -> some View {
        padding(.horizontal, 12)
            .frame(height: height)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

extension Tint {
    var color: Color {
        switch self {
        case .normal: .barWhite
        case .green: .barGreen
        case .yellow: .barYellow
        case .red: .barRed
        }
    }
}

struct WidgetView: View {
    let model: BarModel
    let widget: LiquidBarCore.Widget
    let screenFrame: CGRect
    let itemHeight: CGFloat

    var body: some View {
        switch widget {
        case .apple:
            AppleButton(model: model, screenFrame: screenFrame, height: itemHeight)
        case .workspaces:
            WorkspaceStrip(model: model, itemHeight: itemHeight)
        case .volume:
            Image(systemName: model.volume.symbol)
        case .wifi:
            Image(systemName: model.network.symbol)
                .contentTransition(.symbolEffect(.replace))
        case .battery:
            if let battery = model.battery {
                HStack(spacing: 5) {
                    Image(systemName: battery.symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(battery.tint.color, Color.barWhite.opacity(0.55))
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(battery.percent)%")
                        .font(.system(size: 12, weight: .bold))
                        .contentTransition(.numericText(value: Double(battery.percent)))
                }
                .animation(.smooth, value: battery)
            }
        case .clock:
            Text(clockText(model.now))
                .contentTransition(.numericText())
                .animation(.smooth, value: model.now)
        case .date:
            Text(dateText(model.now))
                .contentTransition(.numericText())
                .animation(.smooth, value: model.now)
        case .script(let script):
            HStack(spacing: 5) {
                if let symbol = script.symbol { Image(systemName: symbol) }
                if let label = model.scriptLabels[script.script], !label.isEmpty {
                    Text(label).contentTransition(.numericText())
                }
            }
            .animation(.smooth, value: model.scriptLabels[script.script])
        }
    }
}

/// Icon only at rest; hovering or scrolling expands it to show the level, collapsing 1.5s after the last interaction.
struct VolumeItem: View {
    let model: BarModel
    let height: CGFloat
    @State private var expanded = false
    @State private var hovering = false
    @State private var collapse: Task<Void, Never>?

    var body: some View {
        let level = model.volume.muted ? 0 : model.volume.level
        HStack(spacing: 8) {
            Image(systemName: model.volume.symbol)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
            if expanded {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 48, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.barWhite).frame(width: 48 * CGFloat(level) / 100)
                    }
                    .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
                Text("\(level)%")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, alignment: .trailing)
                    .contentTransition(.numericText(value: Double(level)))
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: level)
        .pill(height: height)
        .onHover { inside in
            hovering = inside
            inside ? expand() : scheduleCollapse()
        }
        .overlay {
            ScrollCatcher { steps in
                model.nudgeVolume(steps)
                expand()
                if !hovering { scheduleCollapse() }
            }
        }
    }

    private func expand() {
        collapse?.cancel()
        if !expanded { withAnimation(spring) { expanded = true } }
    }

    private func scheduleCollapse() {
        collapse?.cancel()
        collapse = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(spring) { expanded = false }
        }
    }
}

/// SwiftUI has no scroll-wheel hook for plain views; this overlay takes only scroll events and lets clicks and hover through.
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: (Int) -> Void = { _ in }
        private var pending: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            // Device direction: wheel away / fingers up raises the volume regardless of natural scrolling.
            let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
            guard event.hasPreciseScrollingDeltas else {
                if delta != 0 { onScroll(delta > 0 ? 1 : -1) }
                return
            }
            pending += delta / 10
            let steps = Int(pending)
            if steps != 0 {
                pending -= CGFloat(steps)
                onScroll(steps)
            }
            if event.phase == .ended || event.momentumPhase == .ended { pending = 0 }
        }
    }
}

struct AppleButton: View {
    let model: BarModel
    let screenFrame: CGRect
    let height: CGFloat
    @State private var frame = CGRect.zero
    @State private var hovering = false

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: height)
            .background { if hovering { Capsule().fill(.white.opacity(0.07)) } }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture {
                if let command = model.config.clicks["apple"] {
                    shell(command)
                } else {
                    AppleMenu.popUp(at: NSPoint(x: screenFrame.minX + frame.minX, y: screenFrame.maxY - model.config.height + 2))
                }
            }
    }
}

struct WorkspaceStrip: View {
    let model: BarModel
    let itemHeight: CGFloat
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.config.workspaces) { workspace in
                WorkspaceButton(
                    workspace: workspace,
                    focused: model.workspaces.focused == workspace.id,
                    occupied: model.workspaces.occupied.contains(workspace.id),
                    height: itemHeight,
                    ns: ns
                ) { model.focus(workspace.id) }
            }
            if model.workspaces.mode != "main" {
                Text(model.workspaces.mode)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.barYellow)
                    .padding(.horizontal, 9)
                    .frame(height: itemHeight - 4)
                    .background(Capsule().fill(Color.barYellow.opacity(0.18)))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(spring, value: model.workspaces.focused)
        .animation(spring, value: model.workspaces.mode)
    }
}

struct WorkspaceButton: View {
    let workspace: Workspace
    let focused: Bool
    let occupied: Bool
    let height: CGFloat
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: workspace.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
                .symbolEffect(.bounce, value: bounce)
            Text(workspace.id)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(focused ? Color.barWhite : occupied ? Color.barWhite.opacity(0.7) : Color(hex: 0x8b888f, opacity: 0.6))
        .padding(.horizontal, 8)
        .frame(height: height)
        .background {
            if focused {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    .matchedGeometryEffect(id: "focus", in: ns)
            } else if hovering {
                Capsule().fill(.white.opacity(0.07))
            }
        }
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .onChange(of: focused) { if focused { bounce += 1 } }
    }
}
