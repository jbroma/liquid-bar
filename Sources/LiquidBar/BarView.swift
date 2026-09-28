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

    /// The system's primary label colour, white in the bar's dark appearance, so text adapts to the glass under it.
    static let barWhite = Color.primary
    static let barGreen = Color(hex: 0x7bd88f)
    static let barYellow = Color(hex: 0xfce566)
    static let barRed = Color(hex: 0xfc618d)
}

/// One bar per screen.
struct BarView: View {
    let model: BarModel
    @Environment(\.bar) private var bar
    @State private var menuMode = MenuMode()

    var body: some View {
        let config = model.config
        HStack(spacing: 0) {
            island(config.left, alignment: .leading, width: bar.left)
            Spacer(minLength: 0)
            island(config.right, alignment: .trailing, width: bar.right)
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .environment(menuMode)
        .onChange(of: model.frontApp?.pid) { menuMode.end() }
        .frame(maxWidth: .infinity)
        .frame(height: bar.height)
        .background { Color.clear.glassEffect(.regular, in: .rect) }
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
        default: true
        }
    }

    private func island(_ widgets: [LiquidBarCore.Widget], alignment: Alignment, width: CGFloat?) -> some View {
        let leading = alignment == .leading
        let shown = widgets.filter(isShown)
        // The outermost item's hit area runs on to the screen edge, so a pointer thrown into the corner lands on it.
        let outer = leading ? shown.first : shown.last
        let reach = model.config.margin - itemGap / 2
        let edgeReach = leading ? EdgeInsets(top: 0, leading: reach, bottom: 0, trailing: 0) : EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: reach)
        return GlassEffectContainer(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(shown, id: \.self) { widget in
                    WidgetView(model: model, widget: widget)
                        .environment(\.edgeReach, widget == outer ? edgeReach : EdgeInsets())
                }
            }
            .animation(spring, value: model.nowPlaying == nil)
        }
        // Islands get a finite width beside the notch. Each item's hit area already reaches half a gap past it.
        .padding(leading ? .trailing : .leading, 8 - itemGap / 2)
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
    static let gradient = LinearGradient(stops: [.init(color: .white.opacity(0.5), location: 0), .init(color: .white.opacity(0), location: 0.45),
                                                 .init(color: .white.opacity(0.1), location: 1)], startPoint: .top, endPoint: .bottom)

    var body: some View {
        Capsule()
            .strokeBorder(Self.gradient, lineWidth: 0.5)
            .allowsHitTesting(false)
    }
}

extension Tint {
    var color: Color {
        switch self {
        // Solid white, unlike the translucent label colour, so the battery fill reads at rest.
        case .normal: Color(hex: 0xf7f1ff)
        case .green: .barGreen
        case .red: .barRed
        }
    }
}

struct WidgetView: View {
    let model: BarModel
    let widget: LiquidBarCore.Widget
    @Environment(MenuMode.self) private var menuMode
    @Environment(\.bar) private var bar

    var body: some View {
        // Widgets with their own clicks, like the workspaces, take the tap first.
        item.onTapGesture { model.click(widget) }
    }

    @ViewBuilder private var item: some View {
        switch widget {
        case .apple:
            AppleButton(model: model)
        case .workspaces:
            Group {
                if let titles = menuMode.titles {
                    MenuStrip(titles: titles, openTitle: menuMode.openTitle) { menuMode.open($0, columns: $1) }
                        .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                } else {
                    WorkspaceStrip(model: model) { frame in
                        // Clicking the focused workspace, whose front app is in front, shows that app's menus.
                        if let app = model.frontApp { menuMode.toggle(app, at: bar.menuOrigin(under: frame)) }
                    }
                    .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .barHitArea()
        case .nowPlaying:
            if let nowPlaying = model.nowPlaying {
                MenuPill(id: .nowPlaying, pulse: nowPlaying.trackID, padding: 4) {
                    NowPlayingLabel(nowPlaying: nowPlaying, artwork: model.artwork)
                }
                .transition(.scale(0.6).combined(with: .opacity))
            }
        case .volume:
            MenuPill(id: .volume, pulse: model.volume) {
                Image(systemName: model.volume.symbol)
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            // Scroll changes the level in steps of 2.
            .overlay { ScrollCatcher { model.nudgeVolume($0) } }
        case .wifi:
            MenuPill(id: .wifi, pulse: model.network.kind) {
                Image(systemName: model.network.symbol)
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
        case .battery:
            if let battery = model.battery {
                MenuPill(id: .battery, pulse: battery.onAC) { BatteryLabel(battery: battery) }
            }
        case .controlCenter:
            MenuPill(id: .controlCenter, pulse: 0) { Image(systemName: "switch.2").frame(width: 16) }
        case .clock:
            // No transition on the minute flip: animating it costs ~0.2s of CPU every minute at rest.
            MenuPill(id: .clock, pulse: 0) { Text(clockText(model.now)) }
        case .script(let script):
            HStack(spacing: 5) {
                if let symbol = script.symbol { Image(systemName: symbol) }
                if let label = model.scriptLabels[script.script], !label.isEmpty {
                    Text(label).contentTransition(.numericText())
                }
            }
            .animation(spring, value: model.scriptLabels[script.script])
            .fixedSize()
            .pill(height: bar.pill)
            .barHitArea()
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

/// One screen's bar: its frame and height, and the sizes and menu positions that follow from them.
struct BarMetrics {
    var screen = CGRect.zero
    var height: CGFloat = 33
    /// The widths beside the notch; nil without one.
    var left: CGFloat?
    var right: CGFloat?
    var pill: CGFloat { height - 8 }
    /// A workspace, drawn straight on the bar.
    var item: CGFloat { pill - 3 }

    /// Where a menu under `rect`, a global frame in the bar, opens: its left edge, at the bar's bottom. AppKit keeps a
    /// menu below the menu bar's strip and scrolls it instead, hiding its first item, so any higher and it is lost.
    func menuOrigin(under rect: CGRect) -> NSPoint {
        column(under: rect).origin
    }

    /// The bar's full height under `rect`, a global frame in the bar, in screen coordinates.
    func column(under rect: CGRect) -> CGRect {
        CGRect(x: screen.minX + rect.minX, y: screen.maxY - height, width: rect.width, height: height)
    }
}

extension EnvironmentValues {
    @Entry var bar = BarMetrics()
}

struct AppleButton: View {
    let model: BarModel
    @Environment(\.bar) private var bar
    @State private var frame = CGRect.zero
    @State private var hovering = false

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 14, weight: .semibold))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .padding(.horizontal, 3)
            .background { hoverFill(hovering).frame(width: bar.item, height: bar.item) }
            .barHitArea()
            .onHover { hovering = $0 }
            .onTapGesture {
                if let command = model.config.clicks["apple"] {
                    shell(command)
                } else {
                    AppleMenu.popUp(at: bar.menuOrigin(under: frame))
                }
            }
    }
}

/// Scrolling over the strip steps through the workspaces that have windows. A soft fill marks the focused
/// workspace and flows between workspaces like a droplet.
struct WorkspaceStrip: View {
    let model: BarModel
    @Environment(\.bar) private var bar
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
                    stack: model.workspaces.stack(on: workspace.id),
                    focused: focused == workspace.id,
                    height: bar.item
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
                    .frame(height: bar.item - 4)
                    .background(Capsule().fill(Color.barYellow.opacity(0.18)))
                    .padding(.leading, 4)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .background(alignment: .leading) {
            if let focusedFrame {
                DropletShape(lead: lead, trail: trail, rest: focusedFrame.width)
                    .fill(.white.opacity(0.14))
                    .frame(height: bar.item)
            }
        }
        .coordinateSpace(.named("strip"))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { stripOrigin = $0 }
        .onChange(of: focusedFrame) { old, new in
            guard let new else { return }
            guard let old, abs(old.midX - new.midX) > 1 else {
                // Same workspace growing or shrinking (its first window arrived or its last left): both edges together.
                return withAnimation(old == nil ? nil : spring) { (lead, trail) = (new.minX, new.maxX) }
            }
            // A droplet: the edge in the direction of travel leaves first, the other follows 80ms later.
            let right = new.midX > old.midX
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { if right { trail = new.maxX } else { lead = new.minX } }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8).delay(0.08)) { if right { lead = new.minX } else { trail = new.maxX } }
        }
        .opacity(model.aerospaceConnected ? 1 : 0.4)
        .animation(spring, value: model.workspaces.mode)
        .animation(spring, value: model.workspaces.windows)
        .animation(spring, value: model.aerospaceConnected)
        // Wheel away or fingers up goes to the previous workspace, like scrolling up a list.
        .overlay { ScrollCatcher(step: 30) { model.scrollWorkspaces(-$0) } }
    }
}

/// A workspace shows its number beside a card stack of its apps' icons, or only the number when it has no windows.
/// It never changes width on hover, so the strip never shifts under the pointer; its apps show in a dropdown instead.
struct WorkspaceButton: View {
    let id: String
    let stack: (apps: [WorkspaceApp], more: Int)
    let focused: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        LivePill(id: .workspace(id), pulse: 0, gap: 0) { open in
            HStack(spacing: 4) {
                Text(id)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.barWhite.opacity(focused ? 0.9 : stack.apps.isEmpty ? 0.35 : 0.6))
                if !stack.apps.isEmpty {
                    IconStack(apps: stack.apps, more: stack.more)
                }
            }
            .padding(.horizontal, stack.apps.isEmpty ? 7 : 6)
            .frame(minWidth: height, minHeight: height)
            .background { hoverFill(open && !focused) }
        }
        .onTapGesture(perform: action)
    }
}

/// Overlapping icon cards, the first on top and leftmost, each further one smaller and dimmer, then "+N".
struct IconStack: View {
    let apps: [WorkspaceApp]
    let more: Int
    private let size: CGFloat = 16
    private let peek: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                ForEach(Array(apps.enumerated()), id: \.element.bundleID) { index, app in
                    let depth = CGFloat(index)
                    Image(nsImage: AppIcons.icon(app.bundleID))
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .scaleEffect(1 - 0.1 * depth)
                        .opacity(1 - 0.2 * depth)
                        .offset(x: depth * peek)
                        .zIndex(-depth)
                        .transition(.scale(0.5).combined(with: .opacity))
                }
            }
            .frame(width: size + CGFloat(apps.count - 1) * peek, alignment: .leading)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.barWhite.opacity(0.7))
                    .contentTransition(.numericText())
            }
        }
    }
}

/// Under the pointer, the Apple glyph and the workspaces show a fill half as strong as the focused workspace's.
private func hoverFill(_ on: Bool) -> some View {
    Capsule()
        .fill(.white.opacity(on ? 0.07 : 0))
        .animation(.easeOut(duration: 0.15), value: on)
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

    /// The running app's name, like "WezTerm".
    static func name(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
    }
}
