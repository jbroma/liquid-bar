import AppKit
import ApplicationServices
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
            island(config.right, pinned: model.pinnedExtras, alignment: .trailing, width: bar.right)
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .environment(menuMode)
        .environment(\.pills, config.pills)
        .onChange(of: model.frontApp?.pid) { menuMode.end() }
        .frame(maxWidth: .infinity)
        .frame(height: bar.height)
        .background(alignment: .top) { backing }
        .background(alignment: .top) { desktop }
        .animation(.easeOut(duration: 0.1), value: model.missionControl)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                menuMode.hover(true, app: model.frontApp)
            case .ended:
                menuMode.hover(false)
            }
        }
    }

    /// An opaque copy of what is behind the bar, under everything else it draws: the desktop picture, or black over
    /// a full-screen window. With it the native menu bar never shows through, whatever the background.
    @ViewBuilder private var desktop: some View {
        let key = NSStringFromRect(bar.screen)
        if model.coveredScreens.contains(key) {
            Color.black
        } else if let strip = model.desktopStrips[key] {
            Image(decorative: strip, scale: CGFloat(strip.height) / bar.height).resizable().frame(height: bar.height)
        }
    }

    @ViewBuilder private var backing: some View {
        let config = model.config
        Group {
            if config.notchCurve, config.background != .none, let left = bar.left, let right = bar.right {
                // The background's lower edge rises into the notch's sides, so the bar is slimmer beside it.
                let outline = BarOutline(notch: left...(bar.screen.width - right), top: bar.height)
                Group {
                    if config.background == .black {
                        outline.fill(.black)
                    } else {
                        BarBackground(style: config.glass.background, outline: outline)
                    }
                }
            } else {
                switch config.background {
                case .glass: BarBackground(style: config.glass.background)
                case .black: Color.black
                case .none:
                    // Without a copy of the desktop picture, a frosted strip while Mission Control is up: as it
                    // closes, macOS shows the native menu bar for a few frames, which a clear bar would let through.
                    FrostedCover(shown: model.missionControl && model.desktopStrips.isEmpty)
                }
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

    private func island(_ widgets: [LiquidBarCore.Widget], pinned: [MenuExtra<AXUIElement>] = [], alignment: Alignment, width: CGFloat?) -> some View {
        let leading = alignment == .leading
        let shown = widgets.filter(isShown)
        // The outermost item's hit area runs on to the screen edge, so a pointer thrown into the corner lands on it.
        let outer = leading ? shown.first : shown.last
        let reach = model.config.margin - itemGap / 2
        let edgeReach = leading ? EdgeInsets(top: 0, leading: reach, bottom: 0, trailing: 0) : EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: reach)
        return HStack(spacing: 0) {
            if !pinned.isEmpty { PinnedGroup(extras: pinned).transition(.scale(0.6).combined(with: .opacity)) }
            ForEach(shown, id: \.self) { widget in
                WidgetView(model: model, widget: widget)
                    .environment(\.edgeReach, widget == outer ? edgeReach : EdgeInsets())
            }
        }
        .background {
            if model.config.pills == .grouped, !(shown.isEmpty && pinned.isEmpty) {
                // One capsule behind the whole island. The items' hit areas run half a gap past them, and the
                // outermost one's on to the screen edge; the capsule ends 4 points past the items themselves.
                PillBackground(height: bar.pill)
                    .frame(height: bar.pill)
                    .padding(.horizontal, itemGap / 2 - 4)
                    .padding(leading ? .leading : .trailing, reach)
            }
        }
        .animation(spring, value: model.nowPlaying == nil)
        .animation(spring, value: pinned.map(\.bundleID))
        // Islands get a finite width beside the notch. Each item's hit area already reaches half a gap past it.
        .padding(leading ? .trailing : .leading, 8 - itemGap / 2)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

extension View {
    /// A capsule in the style's pill fill, which the focused workspace shares, a step brighter while `lit`. Unless
    /// the pills are separate, only the lit step shows.
    func pill(height: CGFloat, padding: CGFloat = 10, lit: Bool = false) -> some View {
        modifier(Pill(height: height, padding: padding, lit: lit))
    }
}

private struct Pill: ViewModifier {
    let height: CGFloat
    let padding: CGFloat
    let lit: Bool
    @Environment(\.pills) private var pills

    /// Without a pill of its own, an item sits as close as the native menu bar's status items, about 20pt apart with
    /// the gap, and does not widen when lit, which would shift its neighbours.
    func body(content: Content) -> some View {
        let pills = pills == .separate
        content
            .padding(.horizontal, pills ? padding + (lit ? 3 : 0) : 7)
            .frame(height: height)
            .contentShape(Capsule())
            .background {
                if pills { PillBackground(height: height) }
                hoverFill(lit)
            }
    }
}

extension Tint {
    var color: Color {
        switch self {
        // Solid white, unlike the translucent label colour, so the battery fill reads at rest.
        case .normal: Color(hex: 0xf7f1ff)
        case .red: .barRed
        }
    }
}

struct WidgetView: View {
    let model: BarModel
    let widget: LiquidBarCore.Widget
    @Environment(MenuMode.self) private var menuMode
    @Environment(ExpansionSlot.self) private var slot
    @Environment(\.bar) private var bar

    var body: some View {
        // Widgets with their own clicks, like the workspaces, take the tap first.
        item.onTapGesture { model.click(widget) }
    }

    @ViewBuilder private var item: some View {
        switch widget {
        case .apple:
            AppleButton()
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
                // A new track shows in the pill itself rather than opening the dropdown.
                MenuPill(id: .nowPlaying, pulse: 0, padding: 4) {
                    NowPlayingLabel(nowPlaying: nowPlaying, artwork: model.artwork, showsTitle: slot.inline == .nowPlaying)
                }
                .onChange(of: nowPlaying.trackID) { slot.showInline(.nowPlaying, nowPlaying.trackID) }
                .animation(spring, value: nowPlaying.trackID)
                .transition(.scale(0.6).combined(with: .opacity))
            }
        case .volume:
            // macOS shows its own volume overlay, so a change does not open the dropdown.
            MenuPill(id: .volume, pulse: 0) {
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
                MenuPill(id: .battery, pulse: battery.onAC) { BatteryLabel(battery: battery, percent: model.config.batteryPercent) }
            }
        case .controlCenter:
            // A moon while a Focus is on. The native menu bar shows the Focus's own symbol, but which Focus is on needs Full Disk Access to read.
            MenuPill(id: .controlCenter, pulse: 0) {
                HStack(spacing: 8) {
                    if model.controls.state.focus == true { Image(systemName: "moon.fill").transition(.scale.combined(with: .opacity)) }
                    Image(systemName: "switch.2").frame(width: 16)
                }
            }
            .animation(spring, value: model.controls.state.focus)
        case .clock:
            // No transition on the minute flip: animating it costs ~0.2s of CPU every minute at rest.
            // While macOS shows its privacy dot, the pill makes room for it, so the dot sits inside the pill after the time.
            // Without a pill of its own the clock's inset is 7 points smaller, so the room grows by as much.
            MenuPill(id: .clock, pulse: 0, padding: 14) {
                Text(clockText(model.now, hour24: model.config.clock24Hour ?? uses24HourClock(), seconds: model.config.clockSeconds))
                    .padding(.trailing, model.privacyDot ? (model.config.pills == .separate ? 4 : 11) : 0)
            }
                .animation(spring, value: model.privacyDot)
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

/// SwiftUI has no scroll-wheel hook for plain views; this overlay takes only scroll events and lets clicks and hover
/// through. It reports steps up or right as positive.
struct ScrollCatcher: NSViewRepresentable {
    /// Points of precise (trackpad) scrolling per step.
    var step: CGFloat = 10
    /// Steps per notch of a mouse wheel.
    var notch = 1
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.step = step
        view.notch = notch
    }

    final class CatcherView: NSView {
        var onScroll: (Int) -> Void = { _ in }
        var step: CGFloat = 10
        var notch = 1
        private var pending: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            // Device direction: wheel away or fingers up or right raise the level regardless of natural scrolling.
            // AppKit reports scrolling right as a negative x.
            let (dx, dy) = (event.scrollingDeltaX, event.scrollingDeltaY)
            let delta = (abs(dx) > abs(dy) ? -dx : dy) * (event.isDirectionInvertedFromDevice ? -1 : 1)
            guard event.hasPreciseScrollingDeltas else {
                if delta != 0 { onScroll(delta > 0 ? notch : -notch) }
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

    /// Where a menu under `rect`, a global frame in the bar, opens: its left edge, at the bar's bottom.
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
    /// The config's `pills`: whether items sit in their own capsules, in one per side, or straight on the bar.
    @Entry var pills = PillLayout.separate
}

struct AppleButton: View {
    @Environment(\.bar) private var bar
    @Environment(\.pills) private var pills

    var body: some View {
        // With separate glass pills it is a round glass button beside the workspaces' capsule, as a lone button sits
        // beside iOS's tab bar. Otherwise it is bare, inside the shared capsule or on the bar.
        let button = pills == .separate && delegate.model.config.pillGlass
        LivePill(id: .apple, pulse: 0) { open in
            Image(systemName: "apple.logo")
                .font(.system(size: 14, weight: .semibold))
                // The logo's ink sits low and right of its box.
                .offset(x: button ? -0.5 : 0, y: button ? -1 : 0)
                .padding(.horizontal, 3)
                // Open, it widens by 3 points on each side, as the pills on the right do.
                .frame(width: button ? bar.pill + (open ? 6 : 0) : nil, height: button ? bar.pill : nil)
                .background {
                    if button { PillBackground(height: bar.pill) }
                    hoverFill(open).frame(width: button ? nil : bar.item, height: button ? bar.pill : bar.item)
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
    @Environment(\.pills) private var pills
    @State private var frames: [String: CGRect] = [:]
    @State private var lead: CGFloat = 0
    @State private var trail: CGFloat = 0
    @State private var stripOrigin = CGPoint.zero
    /// Where the selection last set off from, for the lens's lift.
    @State private var origin = CGRect.zero

    var body: some View {
        let focused = model.workspaces.focused
        let focusedFrame = focused.flatMap { frames[$0] }
        // In glass, the strip is a tab bar like iOS's: a glass capsule whose selection is a lens.
        // Without pills the selection stays, with no capsule around the strip.
        let lens = model.config.pillGlass
        // The lens sits 3 points inside its capsule on every side, so their corners are concentric.
        let item = lens && pills != .none ? bar.pill - 6 : bar.item
        HStack(spacing: 0) {
            ForEach(model.workspaces.ids, id: \.self) { id in
                WorkspaceButton(
                    id: id,
                    numbered: model.workspaces.numbered,
                    stack: model.workspaces.stack(on: id),
                    focused: focused == id,
                    height: item
                ) {
                    if focused == id, let frame = frames[id] {
                        focusedTap(frame.offsetBy(dx: stripOrigin.x, dy: 0))
                    } else {
                        model.focus(id)
                    }
                }
                .modifier(LensMagnify(lead: lead, trail: trail, from: origin, to: focusedFrame ?? .zero, frame: lens ? frames[id] : nil))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("strip")) } action: { frames[id] = $0 }
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
                let droplet = DropletShape(lead: lead, trail: trail, rest: focusedFrame.width)
                if lens {
                    // Glass redraws its insides whenever its frame changes, which cost 300ms of CPU per move. So the
                    // glass only ever rests on a workspace, and fades out while a drawn lens makes the trip.
                    PillBackground(height: item)
                        .modifier(LensRest(lead: lead, trail: trail, from: origin, to: focusedFrame, height: item))
                    Capsule().fill(.white.opacity(0.1))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .modifier(LensFrame(lead: lead, trail: trail, from: origin, to: focusedFrame, height: item))
                } else {
                    PillFill(shape: droplet).frame(height: bar.item)
                }
            }
        }
        .coordinateSpace(.named("strip"))
        // The tab bar's capsule. Grouped pills already have one around the whole side.
        .padding(.horizontal, lens && pills == .separate ? 3 : 0)
        .background { if lens, pills == .separate { PillBackground(height: bar.pill).frame(height: bar.pill) } }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { stripOrigin = $0 }
        .onChange(of: focusedFrame) { old, new in
            guard let new else { return }
            guard let old, abs(old.midX - new.midX) > 1 else {
                // Same workspace growing or shrinking (its first window arrived or its last left): both edges together,
                // with no trip to lift for.
                origin = new
                return withAnimation(old == nil ? nil : spring) { (lead, trail) = (new.minX, new.maxX) }
            }
            // A droplet: the edge in the direction of travel moves on a faster spring than the one behind it, so it
            // stretches on the way, as the selection of iOS's tab bar does.
            let right = new.midX > old.midX
            origin = CGRect(x: lead, y: 0, width: trail - lead, height: 0)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { if right { trail = new.maxX } else { lead = new.minX } }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { if right { lead = new.minX } else { trail = new.maxX } }
        }
        .opacity(model.workspacesConnected ? 1 : 0.4)
        .animation(spring, value: model.workspaces.mode)
        .animation(spring, value: model.workspaces.windows)
        .animation(spring, value: model.workspacesConnected)
        // Wheel away or fingers up goes to the previous workspace, like scrolling up a list.
        .overlay { ScrollCatcher(step: 30) { model.scrollWorkspaces(-$0) } }
    }
}

/// A workspace shows a card stack of its apps' icons, or a dot when it has no windows, which becomes its number while it is focused.
/// It never changes width on hover, so the strip never shifts under the pointer; its apps show in a dropdown instead.
struct WorkspaceButton: View {
    let id: String
    let numbered: Bool
    let stack: (apps: [WorkspaceApp], more: Int)
    let focused: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        LivePill(id: .workspace(id), pulse: 0, gap: 0) { open in
            // A workspace keeps its width when it gains or loses the focus, so the strip never shifts under the moving
            // selection: its apps, or without windows a dot, which the focused one swaps for its number in place.
            let empty = stack.apps.isEmpty
            ZStack {
                if empty, numbered {
                    Text(id).opacity(focused ? 1 : 0)
                    Circle().fill(Color.barWhite.opacity(0.35)).frame(width: 4, height: 4).opacity(focused ? 0 : 1)
                }
                if !empty { IconStack(apps: stack.apps, more: stack.more) }
            }
            // Under the pointer it grows a little, as the pills on the right do, without moving its neighbours.
            .scaleEffect(open ? 1.12 : 1)
            .padding(.horizontal, empty ? 0 : 7)
            .frame(minWidth: empty ? height + 4 : height, minHeight: height)
            .background { hoverFill(open && !focused) }
        }
        .onTapGesture(perform: action)
    }
}

/// How lifted the selection is on its way `from` one workspace `to` the next, from 0 at either end to 1 in between.
nonisolated func lensLift(lead: CGFloat, trail: CGFloat, from: CGRect, to: CGRect) -> CGFloat {
    let left = abs(lead - from.minX) + abs(trail - from.maxX), remaining = abs(lead - to.minX) + abs(trail - to.maxX)
    return max(0, min(1, left / 16, remaining / 36))
}

/// The glass selection at rest on a workspace. It keeps its place and size while the lens is on its way, at the
/// workspace the lens left and then at the one it is going to, and fades out as the lens lifts.
nonisolated struct LensRest: ViewModifier, Animatable {
    var lead: CGFloat
    var trail: CGFloat
    let from: CGRect
    let to: CGRect
    let height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lead, trail) }
        set { (lead, trail) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        let left = abs(lead - from.minX) + abs(trail - from.maxX), remaining = abs(lead - to.minX) + abs(trail - to.maxX)
        // Still lifting off, or already coming down.
        let rect = from.width > 0 && left / 16 < remaining / 36 ? from : to
        content
            // A light wash, so it stands out from the glass of the capsule under it.
            .overlay(Capsule().fill(.white.opacity(0.08)))
            .frame(width: max(rect.width, 1), height: height)
            .offset(x: rect.minX)
            .opacity(1 - lensLift(lead: lead, trail: trail, from: from, to: to))
    }
}

/// The selection of the workspaces on its way, like the lens of iOS's tab bar: from `lead` to `trail`, it lifts,
/// growing past the strip, clear with a bright rim, and shows only while lifted.
nonisolated struct LensFrame: ViewModifier, Animatable {
    var lead: CGFloat
    var trail: CGFloat
    let from: CGRect
    let to: CGRect
    let height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lead, trail) }
        set { (lead, trail) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        let lift = lensLift(lead: lead, trail: trail, from: from, to: to)
        content
            .frame(width: max(trail - lead, 1) + 8 * lift, height: height * (1 + 0.26 * lift))
            .offset(x: lead - 4 * lift)
            .frame(height: height)
            .opacity(lift)
    }
}

/// Magnifies a workspace while the lifted lens passes over it. `frame` is the workspace's own, nil without a lens.
nonisolated struct LensMagnify: ViewModifier, Animatable {
    var lead: CGFloat
    var trail: CGFloat
    let from: CGRect
    let to: CGRect
    let frame: CGRect?

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lead, trail) }
        set { (lead, trail) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        let under = frame.map { max(0, min(trail, $0.maxX) - max(lead, $0.minX)) / max($0.width, 1) } ?? 0
        content.scaleEffect(1 + 0.18 * min(1, under) * lensLift(lead: lead, trail: trail, from: from, to: to))
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
func hoverFill(_ on: Bool) -> some View {
    Capsule()
        .fill(.white.opacity(on ? 0.07 : 0))
        .animation(.easeOut(duration: 0.15), value: on)
}

/// The focus fill between `lead` and `trail`. Stretched wider than its resting width it thins like a droplet.
nonisolated struct DropletShape: Shape {
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

    /// The app's name, like "WezTerm", also while it is not running.
    static func name(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { $0.deletingPathExtension().lastPathComponent }
            ?? bundleID
    }
}

/// The bar's background, `top` tall, whose lower edge curves up into the notch's sides, so the notch stands a little
/// proud of it. `edgeOnly` is that lower edge alone, for a rim.
nonisolated struct BarOutline: Shape {
    let notch: ClosedRange<CGFloat>
    let top: CGFloat
    var edgeOnly = false

    func path(in rect: CGRect) -> Path {
        // How far the edge rises, over an S-curve this wide on each side of the notch.
        let (rise, run): (CGFloat, CGFloat) = (2, 24)
        let (from, to, high) = (notch.lowerBound, notch.upperBound, top - rise)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 20, y: top))
        path.addLine(to: CGPoint(x: from - run, y: top))
        path.addCurve(to: CGPoint(x: from, y: high), control1: CGPoint(x: from - run / 2, y: top), control2: CGPoint(x: from - run / 2, y: high))
        // Straight on behind the notch, whose round corners show a little of it.
        path.addLine(to: CGPoint(x: to, y: high))
        path.addCurve(to: CGPoint(x: to + run, y: top), control1: CGPoint(x: to + run / 2, y: high), control2: CGPoint(x: to + run / 2, y: top))
        path.addLine(to: CGPoint(x: rect.maxX + 20, y: top))
        if !edgeOnly {
            path.addLine(to: CGPoint(x: rect.maxX + 20, y: -20))
            path.addLine(to: CGPoint(x: rect.minX - 20, y: -20))
            path.closeSubpath()
        }
        return path
    }
}

/// The heaviest blur macOS has, of what is behind the window. It is always in the window, clear until `shown`: adding
/// it then made the whole bar vanish for a frame. It appears at once and fades out.
private struct FrostedCover: NSViewRepresentable {
    let shown: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        guard (view.alphaValue > 0.5) != shown else { return }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = shown ? 0 : 0.12
            view.animator().alphaValue = shown ? 1 : 0
        }
    }
}
