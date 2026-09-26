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
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?
    @State private var slot = ExpansionSlot()
    @State private var menuMode = MenuMode()

    var body: some View {
        let config = model.config
        let pillHeight = config.height - 6
        HStack(spacing: 0) {
            island(config.left, alignment: .leading, width: leftWidth, pillHeight: pillHeight)
            Spacer(minLength: 0)
            island(config.right, alignment: .trailing, width: rightWidth, pillHeight: pillHeight)
                // A notification banner slides in right under the right island; step out of its way.
                .offset(y: yielding ? -config.height : 0)
                .opacity(yielding ? 0 : 1)
                .animation(spring, value: yielding)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .environment(slot)
        .environment(menuMode)
        .onChange(of: model.frontApp?.pid) { menuMode.end() }
        .frame(maxWidth: .infinity)
        .frame(height: config.height)
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
        .frame(maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            let band = Band(width: screenFrame.width, depth: config.height, notch: notch)
            band.fill(band.shade)
        }
    }

    private var notch: ClosedRange<CGFloat>? {
        guard let leftWidth, let rightWidth else { return nil }
        return leftWidth...(screenFrame.width - rightWidth)
    }

    private var yielding: Bool {
        guard let banner = model.banner else { return false }
        return banner.minX < screenFrame.maxX && banner.maxX > screenFrame.midX
    }

    private func isShown(_ widget: LiquidBarCore.Widget) -> Bool {
        switch widget {
        case .nowPlaying: model.nowPlaying != nil
        case .battery: model.battery != nil
        default: true
        }
    }

    /// While a pill is expanded it pulls its inner neighbour into one piece of glass; they split again when it
    /// collapses.
    private func fusedIndices(_ widgets: [LiquidBarCore.Widget]) -> Set<Int> {
        guard let owner = slot.owner,
              let index = widgets.firstIndex(where: { $0.name == owner || ($0 == .workspaces && owner.hasPrefix("workspace:")) })
        else { return [] }
        let neighbour = index > 0 ? index - 1 : index + 1
        return neighbour < widgets.count ? [index, neighbour] : []
    }

    private func island(_ widgets: [LiquidBarCore.Widget], alignment: Alignment, width: CGFloat?, pillHeight: CGFloat) -> some View {
        let margin = model.config.margin
        return ZStack(alignment: alignment) {
            GlassEffectContainer(spacing: 4) {
                let shown = widgets.filter(isShown)
                let fused = fusedIndices(shown)
                HStack(spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, pillHeight: pillHeight)
                            .environment(\.fused, fused.contains(index))
                            // Closing the gap brings the two capsules within the container's blending distance, so the
                            // glass flows into one shape with a neck and snaps apart again as the gap reopens.
                            .padding(.trailing, fused.contains(index) && fused.contains(index + 1) ? -6 : 0)
                    }
                }
                .animation(spring, value: fused)
                .animation(spring, value: model.nowPlaying == nil)
            }
        }
        // Islands get a finite width beside the notch, so an expanded pill's detail yields instead of overflowing.
        .padding(alignment == .leading ? .leading : .trailing, margin)
        .padding(alignment == .leading ? .trailing : .leading, 8)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// The dark band behind the bar, flush with the screen top and straight into both screen edges. Under the notch it
/// hangs `chin` deeper and turns pure black, so the band and the hardware notch read as one object. The steps into the
/// chin follow smootherstep, whose slope and curvature are zero at both ends, so the edge bends without a kink.
struct Band: Shape {
    static let chin: CGFloat = 6
    let width: CGFloat
    let depth: CGFloat
    let notch: ClosedRange<CGFloat>?

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: depth))
            if let notch {
                let run: CGFloat = 18
                step(&path, from: CGPoint(x: notch.lowerBound - run, y: depth), to: CGPoint(x: notch.lowerBound, y: depth + Self.chin))
                step(&path, from: CGPoint(x: notch.upperBound, y: depth + Self.chin), to: CGPoint(x: notch.upperBound + run, y: depth))
            }
            path.addLine(to: CGPoint(x: width, y: depth))
            path.addLine(to: CGPoint(x: width, y: 0))
            path.closeSubpath()
        }
    }

    private func step(_ path: inout Path, from a: CGPoint, to b: CGPoint) {
        path.addLine(to: a)
        for i in 1...24 {
            let t = CGFloat(i) / 24
            let s = t * t * t * (t * (t * 6 - 15) + 10)
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * s))
        }
    }

    /// Dark and faintly translucent, deepening to pure black over the last 140 points before the notch.
    var shade: LinearGradient {
        let dark = Color.black.opacity(0.85)
        guard let notch else { return LinearGradient(colors: [dark], startPoint: .leading, endPoint: .trailing) }
        let at = { (x: CGFloat) in max(0, min(1, x / width)) }
        return LinearGradient(stops: [.init(color: dark, location: at(notch.lowerBound - 140)), .init(color: .black, location: at(notch.lowerBound)),
                                      .init(color: .black, location: at(notch.upperBound)), .init(color: dark, location: at(notch.upperBound + 140))],
                              startPoint: .leading, endPoint: .trailing)
    }
}

extension View {
    /// A glass capsule.
    func pill(height: CGFloat, padding: CGFloat = 12) -> some View {
        self.padding(.horizontal, padding)
            .frame(height: height)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay { Specular() }
    }
}

extension EnvironmentValues {
    /// Whether this pill is merged into its neighbour's glass right now.
    @Entry var fused = false
}

/// The glint along a pill's top edge, fading out toward its middle. Fused pills are one piece of glass, which draws
/// its own edge, so theirs step aside.
struct Specular: View {
    @Environment(\.fused) private var fused

    var body: some View {
        Capsule()
            .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.5), location: 0), .init(color: .white.opacity(0), location: 0.45),
                                                 .init(color: .white.opacity(0.1), location: 1)], startPoint: .top, endPoint: .bottom),
                          lineWidth: 0.5)
            .opacity(fused ? 0 : 1)
            .animation(fused ? nil : .easeOut(duration: 0.25).delay(0.15), value: fused)
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
    let pillHeight: CGFloat
    @Environment(MenuMode.self) private var menuMode

    /// The screen point just below the bar at the left edge of `rect`, a global frame in this bar.
    private func belowBar(_ rect: CGRect) -> NSPoint {
        NSPoint(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - model.config.height + 2)
    }

    var body: some View {
        switch widget {
        case .apple:
            AppleButton(model: model, screenFrame: screenFrame)
                .fixedSize()
                .pill(height: pillHeight, padding: 11)
        case .workspaces:
            // One glass pill for both, so swapping workspaces for menus morphs the capsule instead of replacing it.
            Group {
                if let titles = menuMode.titles {
                    MenuStrip(titles: titles) { menuMode.open($0, at: belowBar($1)) }
                        .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                } else {
                    WorkspaceStrip(model: model, itemHeight: pillHeight - 6) { frame in
                        // Clicking the focused workspace, whose front app is in front, shows that app's menus.
                        if let app = model.frontApp { menuMode.toggle(app, at: belowBar(frame)) }
                    }
                    .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
                }
            }
            .fixedSize()
            .pill(height: pillHeight, padding: 3)
        case .nowPlaying:
            if let nowPlaying = model.nowPlaying {
                NowPlayingPill(nowPlaying: nowPlaying, artwork: model.artwork, control: model.control)
                    .pill(height: pillHeight, padding: 6)
                    .transition(.scale(0.6).combined(with: .opacity))
            }
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
            .fixedSize()
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

/// Scrolling over the strip steps through the workspaces that have windows. The focused workspace sits under a
/// droplet lens tinted by the icon of its front app.
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
        HStack(spacing: 2) {
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
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.barYellow)
                    .padding(.horizontal, 9)
                    .frame(height: itemHeight - 4)
                    .background(Capsule().fill(Color.barYellow.opacity(0.18)))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .background(alignment: .leading) {
            if let focusedFrame {
                DropletLens(lead: lead, trail: trail, rest: focusedFrame.width)
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

/// The workspace number beside a stack of its apps' icons, the most recently used on top. Hover fans the stack
/// into a row; a window arriving or leaving fans it out for a moment.
struct WorkspaceButton: View {
    let id: String
    let apps: [String]
    let focused: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        LivePill(id: "workspace:\(id)", pulse: Set(apps)) { expanded in
            HStack(spacing: 5) {
                Text(id)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.barWhite.opacity(focused ? 1 : apps.isEmpty ? 0.38 : 0.7))
                if !apps.isEmpty {
                    IconStack(apps: apps, fanned: expanded)
                }
            }
            .padding(.leading, apps.isEmpty ? 8 : 7)
            .padding(.trailing, apps.isEmpty ? 8 : 5)
            .frame(height: height)
        }
        .contentShape(Capsule())
        .onTapGesture(perform: action)
    }
}

/// The focus lens between `lead` and `trail`. Stretched wider than its resting width it thins like a droplet.
struct DropletLens: View {
    let lead: CGFloat
    let trail: CGFloat
    let rest: CGFloat

    var body: some View {
        let shape = DropletShape(lead: lead, trail: trail, rest: rest)
        ZStack {
            shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom))
            shape.stroke(LinearGradient(stops: [.init(color: .white.opacity(0.6), location: 0), .init(color: .white.opacity(0.08), location: 0.5),
                                                .init(color: .white.opacity(0.18), location: 1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

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

/// App icons as a small card stack (three visible, then "+N"), or fanned out into a row.
struct IconStack: View {
    let apps: [String]
    let fanned: Bool
    private let size: CGFloat = 20
    private let peek: CGFloat = 6

    var body: some View {
        let shown = Array(apps.prefix(fanned ? 8 : 3))
        let extra = apps.count - shown.count
        let step = fanned ? size + 3 : peek
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                ForEach(Array(shown.enumerated()), id: \.element) { index, app in
                    let depth = fanned ? 0 : CGFloat(index)
                    Image(nsImage: AppIcons.icon(app))
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .scaleEffect(1 - 0.14 * depth)
                        .opacity(1 - 0.28 * depth)
                        .offset(x: CGFloat(index) * step)
                        .zIndex(-Double(index))
                        .transition(.scale(0.5).combined(with: .opacity))
                }
            }
            .frame(width: size + CGFloat(shown.count - 1) * step, alignment: .leading)
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.barWhite.opacity(0.7))
                    .contentTransition(.numericText())
            }
        }
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
