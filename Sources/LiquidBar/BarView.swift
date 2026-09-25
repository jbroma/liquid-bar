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

/// One bar per screen. `leftWidth`/`rightWidth` are the areas beside the notch; nil means no notch.
struct BarView: View {
    let model: BarModel
    let screenFrame: CGRect
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?
    /// The auto-hidden native menu bar slides in under us while the pointer is in the strip and its status items
    /// would show through the gaps between pills, so a backdrop covers each side until it has gone again.
    @State private var covering = false
    @State private var uncover: Task<Void, Never>?

    var body: some View {
        let config = model.config
        let pillHeight = config.height - 6
        HStack(spacing: 0) {
            island(config.left, alignment: .leading, width: leftWidth, pillHeight: pillHeight)
            Spacer(minLength: 0)
            island(config.right, alignment: .trailing, width: rightWidth, pillHeight: pillHeight)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            uncover?.cancel()
            if inside {
                withAnimation(spring) { covering = true }
            } else {
                // The native bar lingers for a moment after the pointer leaves.
                uncover = Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    guard !Task.isCancelled else { return }
                    withAnimation(spring) { covering = false }
                }
            }
        }
    }

    private func island(_ widgets: [LiquidBarCore.Widget], alignment: Alignment, width: CGFloat?, pillHeight: CGFloat) -> some View {
        let margin = model.config.margin
        return ZStack(alignment: alignment) {
            if covering {
                Backdrop().transition(.opacity)
            }
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(Array(widgets.enumerated()), id: \.offset) { _, widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, pillHeight: pillHeight)
                    }
                }
            }
        }
        .padding(alignment == .leading ? .leading : .trailing, margin)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// Covers one side of the notch, full strip height, behind the pills and outside their glass container so they
/// keep their own shapes. Tinted clear glass hides the native status items without muddying the pills on top.
struct Backdrop: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.clear.tint(.black.opacity(0.3)), in: .rect)
    }
}

extension View {
    func pill(height: CGFloat, padding: CGFloat = 12) -> some View {
        // Pills size to their content; long detail text caps its own width instead of wrapping.
        fixedSize()
            .padding(.horizontal, padding)
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
    let pillHeight: CGFloat

    var body: some View {
        switch widget {
        case .apple:
            AppleButton(model: model, screenFrame: screenFrame)
                .pill(height: pillHeight, padding: 11)
        case .workspaces:
            WorkspaceStrip(model: model, itemHeight: pillHeight - 6)
                .pill(height: pillHeight, padding: 3)
        case .volume:
            VolumePill(model: model)
                .pill(height: pillHeight)
                .onTapGesture { model.click(widget) }
        case .wifi:
            NetworkPill(network: model.network)
                .pill(height: pillHeight)
                .onTapGesture { model.click(widget) }
        case .battery:
            if let battery = model.battery {
                BatteryPill(battery: battery)
                    .pill(height: pillHeight)
                    .onTapGesture { model.click(widget) }
            }
        case .clock:
            ClockPill(model: model, screenFrame: screenFrame, pillHeight: pillHeight)
        case .script(let script):
            HStack(spacing: 5) {
                if let symbol = script.symbol { Image(systemName: symbol) }
                if let label = model.scriptLabels[script.script], !label.isEmpty {
                    Text(label).contentTransition(.numericText())
                }
            }
            .animation(spring, value: model.scriptLabels[script.script])
            .pill(height: pillHeight)
            .onTapGesture { model.click(widget) }
        }
    }
}

/// SwiftUI has no scroll-wheel hook for plain views; this overlay takes only scroll events and lets clicks and hover through.
struct ScrollCatcher: NSViewRepresentable {
    /// Points of precise (trackpad) scrolling per step.
    var step: CGFloat = 10
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.step = step
    }

    final class CatcherView: NSView {
        var onScroll: (Int) -> Void = { _ in }
        var step: CGFloat = 10
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
            pending += delta / step
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
    @State private var frame = CGRect.zero

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 16, weight: .semibold))
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
