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
    /// Height of the notch, 0 on a screen without one.
    let notchHeight: CGFloat
    /// macOS reveals the auto-hidden native menu bar under us when the pointer touches the top edge, and its status
    /// items would show through the gaps between pills. The band covers it from then until the pointer leaves.
    @State private var banded = false
    @State private var slot = ExpansionSlot()
    @State private var menuMode = MenuMode()
    @State private var retract: Task<Void, Never>?
    @State private var kick: FluidKick?

    var body: some View {
        let config = model.config
        let pillHeight = config.height - 6
        ZStack {
            NotchBand(
                extended: banded,
                notch: leftWidth.flatMap { left in rightWidth.map { left...(screenFrame.width - $0) } },
                restingHeight: notchHeight
            )
            HStack(spacing: 0) {
                vessel(config.left, source: .trailing, width: sideWidth(leftWidth), pillHeight: pillHeight)
                Spacer(minLength: 0)
                vessel(config.right, source: .leading, width: sideWidth(rightWidth), pillHeight: pillHeight)
                    // A notification banner slides in right under the right island; step out of its way.
                    .offset(y: yielding ? -config.height : 0)
                    .opacity(yielding ? 0 : 1)
                    .animation(spring, value: yielding)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .animation(spring, value: ears)
        .environment(slot)
        .environment(menuMode)
        .onChange(of: model.frontApp?.pid) { menuMode.end() }
        .onChange(of: model.nowPlaying?.trackID) { old, new in
            if old != nil, new != nil { kick = FluidKick(item: "nowPlaying", kind: .ripple) }
        }
        .onChange(of: model.battery?.onAC) { old, new in
            if old == false, new == true { kick = FluidKick(item: "battery", kind: .burst) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                retract?.cancel()
                menuMode.hover(true)
                // Pushing into the top edge, where macOS reveals its menu bar, shows the front app's menus.
                if !banded && location.y <= 3 {
                    withAnimation(spring) { banded = true }
                    if let app = model.frontApp { menuMode.show(app) }
                }
            case .ended:
                menuMode.hover(false)
                guard banded else { return }
                // The native bar lingers for a moment after the pointer leaves.
                retract = Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    guard !Task.isCancelled else { return }
                    withAnimation(spring) { banded = false }
                }
            }
        }
    }

    /// Room the notch island's ears take beside the notch.
    private var ears: CGFloat {
        model.config.agents ? IslandGeometry(notch: .zero).earWidth(model.islandContent) : 0
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

    /// The width of one side's vessel: from the screen edge to just short of the notch, less the agent island's
    /// ears. Without a notch each side takes half the screen.
    private func sideWidth(_ area: CGFloat?) -> CGFloat {
        (area ?? screenFrame.width / 2) - ears - model.config.margin - notchGap
    }

    private let notchGap: CGFloat = 8

    /// Where the fluid gathers: under the focused workspace as a droplet, and under the expanded item with spikes.
    private func places(_ frames: [String: CGRect]) -> [Gather] {
        var places: [Gather] = []
        let focus = model.workspaces.focused.map { "workspace:\($0)" }
        if let focus, !menuMode.active, let frame = frames[focus] {
            let tint = model.workspaces.focused.flatMap { model.workspaces.apps(on: $0).first }.flatMap(AppIcons.tint)
            places.append(Gather(id: "droplet", minX: frame.minX + 3, maxX: frame.maxX - 3, height: 0.7,
                                 spikes: slot.owner == focus ? 0.5 : 0, tint: tint?.fluidTint() ?? .zero, flows: true))
        }
        if let owner = slot.owner, owner != focus, let frame = frames[owner] {
            places.append(Gather(id: owner, minX: frame.minX + 2, maxX: frame.maxX - 2, height: 0.6, spikes: spikes(owner),
                                 tint: tint(owner)?.fluidTint() ?? .zero))
        }
        return places
    }

    /// Volume spikes stand as tall as the level; everything else reaches up at half strength.
    private func spikes(_ id: String) -> Double {
        guard id == "volume" else { return 0.5 }
        return model.volume.muted ? 0.05 : max(0.08, Double(model.volume.level) / 100)
    }

    private func tint(_ id: String) -> Color? {
        switch id {
        case "battery": model.battery?.levelTint.color
        case "nowPlaying": model.artworkColors.first?.glassTint.color
        default: id.hasPrefix("workspace:") ? model.workspaces.apps(on: String(id.dropFirst(10))).first.flatMap(AppIcons.tint) : nil
        }
    }

    private func vessel(_ widgets: [LiquidBarCore.Widget], source: FluidSim.End, width: CGFloat, pillHeight: CGFloat) -> some View {
        Vessel(source: source, height: pillHeight, kick: kick, places: places) {
            HStack(spacing: 0) {
                ForEach(widgets.filter(isShown), id: \.self) { widget in
                    WidgetView(model: model, widget: widget, screenFrame: screenFrame, pillHeight: pillHeight)
                }
            }
            .padding(.horizontal, 6)
            .animation(spring, value: model.nowPlaying == nil)
        }
        .frame(width: max(0, width))
        .padding(source == .trailing ? .leading : .trailing, model.config.margin)
    }
}

extension View {
    /// An item's slot in its vessel: its content centred at the bar's item height, clickable edge to edge.
    func pill(height: CGFloat, padding: CGFloat = 10) -> some View {
        self.padding(.horizontal, padding)
            .frame(height: height)
            .contentShape(Rectangle())
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
    @State private var stripOrigin = CGPoint.zero

    var body: some View {
        let focused = model.workspaces.focused
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
        .coordinateSpace(.named("strip"))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { stripOrigin = $0 }
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
