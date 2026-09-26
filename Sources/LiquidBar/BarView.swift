import AppKit
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
    let height: CGFloat
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?
    let slot: ExpansionSlot
    @State private var menuMode = MenuMode()

    var body: some View {
        let config = model.config
        HStack(spacing: 0) {
            island(config.left, alignment: .leading, width: leftWidth)
            Spacer(minLength: 0)
            island(config.right, alignment: .trailing, width: rightWidth)
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .environment(slot)
        .environment(menuMode)
        .onChange(of: model.frontApp?.pid) { menuMode.end() }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                menuMode.hover(true)
                // Pushing into the top edge, where macOS reveals its menu bar, shows the front app's menus.
                if location.y <= 3, let app = model.frontApp { menuMode.show(app) }
            case .ended:
                menuMode.hover(false)
            }
        }
    }

    private func isShown(_ widget: LiquidBarCore.Widget) -> Bool {
        switch widget {
        case .nowPlaying: model.nowPlaying != nil
        case .battery: model.battery != nil
        case .menuExtras: !model.menuExtras.isEmpty
        default: true
        }
    }

    private func island(_ widgets: [LiquidBarCore.Widget], alignment: Alignment, width: CGFloat?) -> some View {
        let margin = model.config.margin
        return ZStack(alignment: alignment) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(widgets.filter(isShown), id: \.self) { widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, barHeight: height)
                    }
                }
                .animation(spring, value: slot.owner)
                .animation(spring, value: model.nowPlaying == nil)
            }
        }
        // Islands get a finite width beside the notch. Each item's hit area already reaches half a gap past it.
        .padding(alignment == .leading ? .leading : .trailing, margin - itemGap / 2)
        .padding(alignment == .leading ? .trailing : .leading, 8 - itemGap / 2)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

extension View {
    /// A glass capsule.
    func pill(height: CGFloat, padding: CGFloat = 10) -> some View {
        self.padding(.horizontal, padding)
            .frame(height: height)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay { Specular() }
    }
}

/// The glint along a pill's top edge, fading out toward its middle.
struct Specular: View {
    var body: some View {
        Capsule()
            .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.5), location: 0), .init(color: .white.opacity(0), location: 0.45),
                                                 .init(color: .white.opacity(0.1), location: 1)], startPoint: .top, endPoint: .bottom),
                          lineWidth: 0.5)
            .allowsHitTesting(false)
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
    let barHeight: CGFloat
    @Environment(MenuMode.self) private var menuMode

    private var pillHeight: CGFloat { barHeight - 8 }

    /// The screen point just below the bar at the left edge of `rect`, a global frame in this bar.
    private func belowBar(_ rect: CGRect) -> NSPoint {
        NSPoint(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - barHeight + 2)
    }

    var body: some View {
        switch widget {
        case .apple:
            AppleButton(model: model, screenFrame: screenFrame, barHeight: barHeight)
        case .workspaces:
            Group {
                if let titles = menuMode.titles {
                    MenuStrip(titles: titles) { menuMode.open($0, at: belowBar($1)) }
                        .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                } else {
                    WorkspaceStrip(model: model, itemHeight: pillHeight - 3) { frame in
                        // Clicking the focused workspace, whose front app is in front, shows that app's menus.
                        if let app = model.frontApp { menuMode.toggle(app, at: belowBar(frame)) }
                    }
                    .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .barHitArea()
        case .nowPlaying:
            if let nowPlaying = model.nowPlaying {
                MenuPill(id: widget.name, pulse: nowPlaying.trackID, height: pillHeight, padding: 4) {
                    NowPlayingLabel(nowPlaying: nowPlaying, artwork: model.artwork)
                }
                .transition(.scale(0.6).combined(with: .opacity))
            }
        case .menuExtras:
            MenuPill(id: widget.name, pulse: 0, height: pillHeight) { Image(systemName: "ellipsis").frame(width: 16) }
        case .volume:
            MenuPill(id: widget.name, pulse: model.volume, height: pillHeight) {
                Image(systemName: model.volume.symbol)
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            // Scroll changes the level in steps of 2.
            .overlay { ScrollCatcher { model.nudgeVolume($0) } }
            .onTapGesture { model.click(widget) }
        case .wifi:
            MenuPill(id: widget.name, pulse: model.network.kind, height: pillHeight) {
                Image(systemName: model.network.symbol)
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            .onTapGesture { model.click(widget) }
        case .battery:
            if let battery = model.battery {
                MenuPill(id: widget.name, pulse: battery.onAC, height: pillHeight) { BatteryLabel(battery: battery) }
                    .onTapGesture { model.click(widget) }
            }
        case .controlCenter:
            // The real Control Center is this item's dropdown, so it never claims the bar's own.
            Image(systemName: "switch.2")
                .frame(width: 16)
                .fixedSize()
                .pill(height: pillHeight)
                .barHitArea()
                .onTapGesture {
                    haptic()
                    MenuExtras.toggleControlCenter(explainAt: NSPoint(x: NSEvent.mouseLocation.x, y: screenFrame.maxY - barHeight + 2))
                }
        case .clock:
            // No transition on the minute flip: animating it costs ~0.2s of CPU every minute at rest.
            MenuPill(id: widget.name, pulse: 0, height: pillHeight) { Text(clockText(model.now)) }
                .onTapGesture { model.click(widget) }
        case .script(let script):
            HStack(spacing: 5) {
                if let symbol = script.symbol { Image(systemName: symbol) }
                if let label = model.scriptLabels[script.script], !label.isEmpty {
                    Text(label).contentTransition(.numericText())
                }
            }
            .animation(spring, value: model.scriptLabels[script.script])
            .fixedSize()
            .pill(height: pillHeight)
            .barHitArea()
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
    let barHeight: CGFloat
    @State private var frame = CGRect.zero

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 14, weight: .semibold))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .padding(.horizontal, 3)
            .barHitArea()
            .onTapGesture {
                if let command = model.config.clicks["apple"] {
                    shell(command)
                } else {
                    AppleMenu.popUp(at: NSPoint(x: screenFrame.minX + frame.minX, y: screenFrame.maxY - barHeight + 2))
                }
            }
    }
}

/// Scrolling over the strip steps through the workspaces that have windows. A soft fill marks the focused
/// workspace and flows between workspaces like a droplet.
struct WorkspaceStrip: View {
    let model: BarModel
    let itemHeight: CGFloat
    /// A click on the already focused workspace, with its global frame.
    let focusedTap: (CGRect) -> Void
    @State private var frames: [String: CGRect] = [:]
    @State private var lead: CGFloat = 0
    @State private var trail: CGFloat = 0
    @State private var stripOrigin = CGPoint.zero

    var body: some View {
        let focused = model.workspaces.focused
        let focusedFrame = focused.flatMap { frames[$0] }
        HStack(spacing: 0) {
            ForEach(model.config.workspaces) { workspace in
                WorkspaceButton(
                    id: workspace.id,
                    apps: model.workspaces.apps(on: workspace.id),
                    focused: focused == workspace.id,
                    height: itemHeight
                ) {
                    if focused == workspace.id, let frame = frames[workspace.id] {
                        focusedTap(frame.offsetBy(dx: stripOrigin.x, dy: 0))
                    } else {
                        model.focus(workspace.id)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("strip")) } action: { frames[workspace.id] = $0 }
            }
            if model.workspaces.mode != "main" {
                Text(model.workspaces.mode)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.barYellow)
                    .padding(.horizontal, 7)
                    .frame(height: itemHeight - 4)
                    .background(Capsule().fill(Color.barYellow.opacity(0.18)))
                    .padding(.leading, 4)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .background(alignment: .leading) {
            if let focusedFrame {
                DropletShape(lead: lead, trail: trail, rest: focusedFrame.width)
                    .fill(.white.opacity(0.14))
                    .frame(height: itemHeight)
            }
        }
        .coordinateSpace(.named("strip"))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { stripOrigin = $0 }
        .onChange(of: focusedFrame) { old, new in
            guard let new else { return }
            guard let old, abs(old.midX - new.midX) > 1 else {
                // Same workspace growing or shrinking (its icons fanned out): both edges together.
                return withAnimation(old == nil ? nil : spring) { (lead, trail) = (new.minX, new.maxX) }
            }
            // A droplet: the edge in the direction of travel leaves first, the other follows 80ms later.
            let right = new.midX > old.midX
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { if right { trail = new.maxX } else { lead = new.minX } }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8).delay(0.08)) { if right { lead = new.minX } else { trail = new.maxX } }
        }
        .animation(spring, value: model.workspaces.mode)
        .animation(spring, value: model.workspaces.windows)
        // Wheel away or fingers up goes to the previous workspace, like scrolling up a list.
        .overlay { ScrollCatcher(step: 30) { model.scrollWorkspaces(-$0) } }
    }
}

/// A workspace shows the icon of its most recently used app, or its number when it has no windows. Hover fans out
/// the icons of all its apps; a window arriving or leaving fans them out for a moment.
struct WorkspaceButton: View {
    let id: String
    let apps: [String]
    let focused: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        LivePill(id: "workspace:\(id)", pulse: Set(apps), gap: 0) { expanded in
            HStack(spacing: 4) {
                Text(id)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.barWhite.opacity(focused ? 0.9 : apps.isEmpty ? 0.35 : 0.6))
                ForEach(apps.prefix(expanded ? 8 : 1), id: \.self) { app in
                    Image(nsImage: AppIcons.icon(app))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .transition(.scale(0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, apps.isEmpty ? 7 : 6)
            .frame(minWidth: height, minHeight: height)
        }
        .onTapGesture(perform: action)
    }
}

/// The focus fill between `lead` and `trail`. Stretched wider than its resting width it thins like a droplet.
struct DropletShape: Shape {
    var lead: CGFloat
    var trail: CGFloat
    let rest: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lead, trail) }
        set { (lead, trail) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(trail - lead, 1)
        // Volume is kept roughly constant: twice as long, about 70% as tall, never thinner than 72%.
        let height = rect.height * min(1, max(0.72, (rest / width).squareRoot()))
        return Path(roundedRect: CGRect(x: lead, y: rect.midY - height / 2, width: width, height: height), cornerRadius: height / 2)
    }
}

/// App icons by bundle ID, looked up once.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ bundleID: String) -> NSImage {
        if let icon = cache[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
        cache[bundleID] = icon
        return icon
    }
}
