import LiquidBarCore
import SwiftUI

/// The items that open a dropdown, and the ids of the `ExpansionSlot`. The Apple logo's and a workspace's hang left of the notch, the rest
/// right of it.
nonisolated enum Dropdown: Hashable, Sendable {
    case nowPlaying, volume, wifi, battery
    /// Open macOS's own Control Center and Notification Center instead of a dropdown.
    case controlCenter, clock
    case apple
    case workspace(String)
    /// A pinned app's status item, by bundle id.
    case menuExtra(String)

    /// The Apple status item whose panel opens in place of a dropdown.
    var nativeItem: String? {
        switch self {
        case .controlCenter: SystemControlCenter.controlCenter
        case .clock: SystemControlCenter.clock
        default: nil
        }
    }

    var isLeft: Bool {
        switch self {
        case .apple, .workspace: true
        default: false
        }
    }

    var width: CGFloat {
        switch self {
        case .nowPlaying: 280
        case .workspace: 220
        case .apple: 240
        default: 264
        }
    }
}

/// The glass menu floating just below the bar under the open item. It floats rather than joining the bar because each
/// window's glass samples a different backdrop, so a joined shape shows a seam. Each side of the notch has its own
/// transparent window below the bar, whose clear pixels pass the pointer through, and shows only its side's dropdowns.
/// Moving to another item morphs it there; its content cross-fades.
struct DropdownView: View {
    let model: BarModel
    /// This window's left edge in the bar window's coordinates.
    let originX: CGFloat
    /// This window is left of the notch, with the screen edge on its left.
    let left: Bool
    @Environment(ExpansionSlot.self) private var slot
    @Environment(\.bar) private var bar
    @State private var heights: [Dropdown: CGFloat] = [:]
    /// The pill the dropdown last hung from.
    @State private var anchor = CGRect.zero
    /// The open dropdown's frame, which the glass keeps while closed, so it is not resized for the next opening.
    @State private var last = Geometry(x: 0, width: 1, height: 1)
    @State private var wasOpen = false
    /// The dropdown that just closed, still drawn while its window fades out.
    @State private var lingering: Dropdown?

    static let corner: CGFloat = 18

    private struct Geometry: Equatable {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    var body: some View {
        let target = slot.owner.flatMap { $0.isLeft == left && hasContent($0) ? $0 : nil }
        let open = target ?? lingering
        let pill = target.flatMap { slot.frames[$0] } ?? anchor
        GeometryReader { proxy in
            let geometry = open == nil ? last : geometry(open, pill: pill, panel: proxy.size)
            // Glass redraws its insides on every animated frame, which made an opening cost half a second of CPU.
            // So the opening and the closing are the window's own fade (`WindowFade`), and SwiftUI animates only a
            // move from one item to the next.
            let morph = wasOpen && target != nil ? spring : nil
            // In the bar's coordinates, reaching up over the gap to the bar so a pointer crossing it stays inside.
            let area = target.map { _ in CGRect(x: originX + geometry.x, y: bar.height, width: geometry.width, height: geometry.height + 6) }
            let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
            // Closed, the glass has no height, so it takes no clicks. It is never made clear: glass that turns
            // visible shows up a few frames after the text on it.
            OverlayGlass(corner: Self.corner)
                .frame(width: geometry.width, height: geometry.height)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        if let open {
                            // Scrolls only when the menu is taller than the screen below the bar.
                            ScrollView {
                                content(open)
                                    .frame(width: open.width)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[open] = $0 }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .id(open)
                            .transition(.opacity)
                        }
                    }
                }
                .clipShape(shape)
                .contentShape(shape)
                // SwiftUI can miss the exit when the dropdown closes under a still pointer, and then never reports
                // the next entry; every move inside reports it again.
                .onContinuousHover { phase in
                    if case .active = phase { slot.hold(true) } else { slot.hold(false) }
                }
                .offset(x: geometry.x, y: 6)
                .animation(morph, value: geometry)
                // An opening or a closing inherits the bar's animation of the open item, which is taken off here.
                .transaction { if morph == nil { $0.animation = nil } }
                .background { WindowFade(visible: target != nil) }
                .onChange(of: area, initial: true) { slot.dropdowns[left] = area }
                .onChange(of: geometry) { if target != nil { last = geometry } }
                .onChange(of: target) { old, new in
                    wasOpen = new != nil
                    lingering = new == nil ? old : nil
                    guard new == nil else { return }
                    Task {
                        try? await Task.sleep(for: .seconds(WindowFade.out))
                        if slot.owner?.isLeft != left { lingering = nil }
                    }
                }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
        .onChange(of: pill) { if target != nil { anchor = pill } }
    }

    /// A workspace with one app or none has nothing to list, and neither has a status item without a menu, nor an item
    /// that opens macOS's own panel.
    private func hasContent(_ dropdown: Dropdown) -> Bool {
        switch dropdown {
        case .controlCenter, .clock: false
        case .workspace(let id): model.workspaces.apps(on: id).count > 1
        case .menuExtra(let id): model.pinnedExtras.first { $0.bundleID == id }?.hasMenu == true
        default: true
        }
    }

    private func geometry(_ open: Dropdown?, pill: CGRect, panel: CGSize) -> Geometry {
        guard let open, let height = heights[open] else { return Geometry(x: pill.minX - originX, width: pill.width, height: 0) }
        // Clear of the notch, and as far in from the screen edges as the panel hangs below the bar.
        let x = dropdownX(center: pill.midX - originX, width: open.width, lower: left ? 6 : 10, upper: panel.width - (left ? 10 : 6))
        return Geometry(x: x, width: open.width, height: min(height, panel.height - 8))
    }

    @ViewBuilder private func content(_ dropdown: Dropdown) -> some View {
        switch dropdown {
        case .volume: VolumeMenu(model: model)
        case .wifi: NetworkMenu(network: model.network)
        case .battery: BatteryMenu(battery: model.battery, percent: model.config.batteryPercent)
        case .apple: AppleMenu()
        case .workspace(let id): WorkspaceMenu(model: model, id: id)
        case .menuExtra(let id): MenuExtraMenu(extra: model.pinnedExtras.first { $0.bundleID == id })
        case .controlCenter, .clock: EmptyView()
        case .nowPlaying: NowPlayingMenu(nowPlaying: model.nowPlaying, artwork: model.artwork, control: model.control)
        }
    }
}

/// Fades the dropdown's window in and out and drops it into place as it appears. The window server blends the
/// window and the render server moves its layer, so the bar draws nothing per frame.
private struct WindowFade: NSViewRepresentable {
    let visible: Bool
    /// Seconds the fade out takes, which the closed dropdown stays drawn for.
    static let out = 0.12

    final class Coordinator { var visible: Bool? }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The window is there only after the first update.
        DispatchQueue.main.async {
            guard let window = view.window, context.coordinator.visible != visible else { return }
            // The first time, the window starts clear rather than fading out from opaque.
            if context.coordinator.visible == nil { window.alphaValue = 0 }
            context.coordinator.visible = visible
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = visible ? 0.16 : Self.out
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = visible ? 1 : 0
            }
            guard visible, let layer = window.contentView?.layer else { return }
            let drop = CASpringAnimation(keyPath: "transform.translation.y")
            // Up is the positive direction of an unflipped layer and the negative one of a flipped one.
            drop.fromValue = layer.isGeometryFlipped ? -8 : 8
            drop.toValue = 0
            drop.damping = 18
            drop.stiffness = 260
            drop.duration = drop.settlingDuration
            layer.add(drop, forKey: "drop")
        }
    }
}

/// The dimmed white of secondary text in the menus.
let secondary = Color.barWhite.opacity(0.55)

/// A menu's stack of rows, inset like the native menus.
struct MenuBody<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }
}

/// A row's standard insets: text lines up with the section titles.
struct MenuRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

/// A row that does something on click.
struct MenuButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        MenuRow(content: content).hoverButton(action: action)
    }
}

extension View {
    /// A click target with the native menus' rounded hover highlight and a haptic tick.
    func hoverButton(radius: CGFloat = 7, action: @escaping () -> Void) -> some View {
        modifier(HoverButton(radius: radius, action: action))
    }

    /// A symbol's circle, filled with the accent colour while `on`, like the controls in Control Center.
    func iconCircle(on: Bool, size: CGFloat) -> some View {
        foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(on ? Color.accentColor : .white.opacity(0.14)))
    }
}

private struct HoverButton: ViewModifier {
    let radius: CGFloat
    let action: () -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(hovering ? 0.12 : 0)) }
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
            .onTapGesture {
                haptic()
                action()
            }
    }
}

/// A title with a control at its end, as tall as a row in a Control Center module, like the "Show Percentage" switch row.
struct HeaderRow<Trailing: View>: View {
    let title: String
    var bold = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        MenuRow {
            Text(title).fontWeight(bold ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 32)
    }
}

/// Control Center's wide switch: an accent track with the knob at its end while on. It dims and ignores clicks while
/// the setting cannot be read.
struct GlassSwitch: View {
    let on: Bool?
    let set: (Bool) -> Void

    var body: some View {
        let isOn = on == true
        Capsule()
            .fill(isOn ? Color.accentColor : .white.opacity(0.2))
            .frame(width: 50, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(.white).frame(width: 30, height: 20).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
            .contentShape(Capsule())
            .onTapGesture {
                haptic()
                set(!isOn)
            }
            .animation(spring, value: isOn)
            .opacity(on == nil ? 0.4 : 1)
            .allowsHitTesting(on != nil)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// "Title" on the left, a dimmed value on the right.
struct MenuValue: View {
    let title: String
    let value: String

    var body: some View {
        MenuRow {
            Text(title).foregroundStyle(secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().lineLimit(1)
        }
    }
}

/// The bold title that opens a menu, with an optional dimmed accessory on the right.
struct MenuTitle: View {
    let title: String
    var accessory: String?

    var body: some View {
        MenuRow {
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 8)
            if let accessory { Text(accessory).foregroundStyle(secondary).monospacedDigit() }
        }
    }
}

/// The dimmed heading of a group of rows, like "Output".
struct MenuSection: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
    }
}

struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }
}

/// "Sound Settings…" and the like, which open a pane in System Settings.
struct SettingsButton: View {
    let title: String
    let pane: String

    var body: some View {
        MenuButton { openSettings(pane) } content: { Text(title) }
    }
}

/// A workspace's apps, the most recent first and the one holding the focused window marked. A click focuses that
/// app's window there and closes the menu, before the rows reorder under the pointer.
struct WorkspaceMenu: View {
    let model: BarModel
    let id: String
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        MenuBody {
            MenuTitle(title: model.workspaces.title(id))
            ForEach(model.workspaces.apps(on: id), id: \.bundleID) { app in
                MenuButton {
                    slot.dismiss()
                    model.focus(window: app.windowID, on: id)
                } content: {
                    Image(nsImage: AppIcons.icon(app.bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(AppIcons.name(app.bundleID)).lineLimit(1)
                    Spacer(minLength: 8)
                    if app.focused { Circle().fill(Color.barWhite).frame(width: 6, height: 6) }
                }
            }
        }
    }
}

/// The dropdowns' and windows' glass in the config's dropdown style, or in `style` for a preview. It follows the config live.
struct OverlayGlass: View {
    let corner: CGFloat
    var style: GlassStyle?
    /// A preset's blur, for its preview; otherwise the config's.
    var blur: Double?

    var body: some View {
        let shown = style ?? delegate.model.config.glass.dropdown
        StyledGlass(corner: corner, style: shown, preview: style != nil, blur: blur ?? delegate.model.config.blur).id(shown)
    }
}

/// A pill's background in the bar style, or in `style` for a preview: the style's real glass, the same as the
/// dropdowns', when the config's `pillGlass` is on, and otherwise its flat fill.
struct PillBackground: View {
    let height: CGFloat
    var style: GlassStyle?
    /// A preview blurs what its own window draws under it.
    var preview = false
    /// A preset's blur, for its preview; otherwise the config's.
    var blur: Double?

    var body: some View {
        let config = delegate.model.config
        if config.pillGlass, preview || config.background == .none {
            let shown = style ?? config.glass.bar
            StyledGlass(corner: height / 2, style: shown, preview: preview, blur: blur ?? config.blur, pill: true).id(shown)
                .overlay { PillSheen(strength: shown.pillSheen) }
        } else if config.pillGlass {
            // Glass never sits on glass: on a bar with a background a pill is a wash and the lit edge. A second
            // layer of glass turned grey over the black bar and doubled the glass one.
            let shown = style ?? config.glass.bar
            // On black every style is the same faint wash: anything stronger reads as a grey slab.
            Capsule().fill(config.background == .black ? Color.white.opacity(0.05) : shown.wash)
            PillSheen(strength: config.background == .black ? min(shown.pillSheen, 0.6) : shown.pillSheen)
        } else {
            PillFill(shape: Capsule(), style: style)
        }
    }
}

/// The light on a glass pill: a lit edge, brightest along the top, and a soft glow under it. The glass's own edge
/// takes its light from what is behind it, so over a dark wallpaper it goes dark and the pill looks flat.
private struct PillSheen: View {
    let strength: Double

    var body: some View {
        Capsule()
            .fill(LinearGradient(stops: [.init(color: .white.opacity(0.16 * strength), location: 0),
                                         .init(color: .white.opacity(0.03 * strength), location: 0.55),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        Capsule()
            .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.7 * strength), location: 0),
                                                 .init(color: .white.opacity(0.18 * strength), location: 0.5),
                                                 .init(color: .white.opacity(0.32 * strength), location: 1)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }
}

extension GlassStyle {
    /// How strongly a glass pill and the bar's background are lit, from the brightest styles to the clearest.
    var pillSheen: Double {
        switch self {
        case .liquid: 1
        case .frost: 0.7
        case .graphite: 0.5
        case .crystal: 0.4
        }
    }

    /// A pill's wash on a bar that has a background.
    fileprivate var wash: Color {
        switch self {
        case .crystal: .white.opacity(0.04)
        case .liquid: .white.opacity(0.07)
        case .frost: .white.opacity(0.12)
        case .graphite: .black.opacity(0.3)
        }
    }
}

/// The strip behind the whole bar, in the bar's glass: the same glass and the same light as a glass pill, so the two
/// match. It runs past the bar on every side, which hides the glass's own edges, and its lower edge is a lit line:
/// straight, or along `outline` where the bar curves into the notch.
struct BarBackground: View {
    let style: GlassStyle
    var preview = false
    var outline: BarOutline?

    var body: some View {
        let strength = style.pillSheen
        let lit = Color.white.opacity(0.4 * strength)
        let glass = StyledGlass(corner: 0, style: style, preview: preview, blur: delegate.model.config.blur, pill: true)
            .id(style)
            .padding(.horizontal, -12)
            .padding(.top, -12)
            .padding(.bottom, -16)
            .overlay { LinearGradient(colors: [.white.opacity(0.1 * strength), .clear], startPoint: .top, endPoint: .bottom) }
        if let outline {
            glass
                // Half of the line falls outside the outline and is cut off with the glass.
                .overlay { BarOutline(notch: outline.notch, top: outline.top, edgeOnly: true).stroke(lit, lineWidth: 2) }
                .mask { outline }
        } else {
            glass
                .overlay(alignment: .bottom) { Rectangle().fill(lit).frame(height: 1) }
                .clipped()
        }
    }
}

/// The fill of a bar pill or of the focused workspace in the config's bar style. Liquid keeps the flat fill:
/// pills in the volume overlay's glass drew heavy white rims at bar height.
struct PillFill<S: Shape>: View {
    let shape: S
    var style: GlassStyle?

    var body: some View {
        let style = style ?? delegate.model.config.glass.bar
        switch style {
        case .liquid: shape.fill(.white.opacity(0.14))
        case .crystal:
            shape.fill(.white.opacity(0.05))
            shape.stroke(.white.opacity(0.3), lineWidth: 1)
        case .frost: shape.fill(.white.opacity(0.2))
        case .graphite: shape.fill(.black.opacity(0.32))
        }
    }
}

private struct StyledGlass: NSViewRepresentable {
    let corner: CGFloat
    let style: GlassStyle
    /// A preview blurs what its own window draws under it rather than what lies behind the window.
    let preview: Bool
    /// The config's `glassBlur`.
    let blur: Double
    /// A pill of the bar rather than a dropdown: glass that reads at 25 points tall.
    var pill = false

    func makeNSView(context: Context) -> NSView {
        let tuned = BlurTunedView()
        let glass = makeGlass()
        glass.frame = tuned.bounds
        glass.autoresizingMask = [.width, .height]
        tuned.addSubview(glass)
        // A pill's clear variants have no blur of their own, and get the clear style's.
        tuned.floor = pill ? 5 : 0
        tuned.blur = blur
        return tuned
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? BlurTunedView)?.blur = blur
    }

    /// A wash over the glass: Graphite's darkens it and Frost's lightens it. The glass's own tint colours regular
    /// glass without darkening it.
    private var wash: NSView? {
        let color: NSColor
        switch style {
        case .graphite: color = NSColor(white: 0, alpha: 0.42)
        case .frost: color = NSColor(white: 1, alpha: 0.09)
        default: return nil
        }
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = corner
        view.layer?.cornerCurve = .continuous
        view.autoresizingMask = [.width, .height]
        return view
    }

    /// A pill's glass, as layers from the bottom up: a private variant of the glass (nil is regular glass) and its
    /// opacity. A dropdown's glass is too heavy at a pill's height, where Liquid's lit rim fills the whole pill.
    /// Variant 19 is clear glass with a fine bright edge: Crystal is that alone, and it is the rim of Liquid's and
    /// Graphite's regular glass. Frost is regular glass with no rim.
    private var pillLayers: [(variant: Int?, opacity: CGFloat)] {
        switch style {
        case .crystal: [(19, 1)]
        case .liquid: [(nil, 1), (19, 0.6)]
        case .frost: [(nil, 1)]
        case .graphite: [(nil, 1), (19, 0.4)]
        }
    }

    private func makePill() -> NSView {
        let probe = NSGlassEffectView()
        guard ["set_variant:", "set_backdropGroupName:"].allSatisfy({ probe.responds(to: Selector($0)) }) else {
            // Without the private setters, the public glass nearest the style.
            probe.cornerRadius = corner
            if style == .crystal { probe.style = .clear }
            guard let wash else { return probe }
            let stack = FillStack()
            for view in [probe, wash] {
                view.autoresizingMask = [.width, .height]
                stack.addSubview(view)
            }
            return stack
        }
        // In one backdrop group each layer samples what is behind the window, not the layer under it.
        let group = UUID().uuidString
        let stack = FillStack()
        for layer in pillLayers {
            let glass = NSGlassEffectView()
            glass.cornerRadius = corner
            if let variant = layer.variant { glass.setValue(variant, forKey: "_variant") }
            glass.setValue(group, forKey: "_backdropGroupName")
            glass.alphaValue = layer.opacity
            glass.autoresizingMask = [.width, .height]
            stack.addSubview(glass)
        }
        if let wash { stack.addSubview(wash) }
        return stack
    }

    private func makeGlass() -> NSView {
        if pill { return makePill() }
        let glass = NSGlassEffectView()
        glass.cornerRadius = corner
        let privateKeys = ["set_variant:", "set_backdropGroupName:"].allSatisfy { glass.responds(to: Selector($0)) }
        let base = NSGlassEffectView()
        base.cornerRadius = corner
        if style == .crystal { base.style = .clear }
        // The lit rim of the private variant 11 around regular glass, as macOS's volume overlay draws it. Liquid is
        // that rim at full strength.
        let rim = NSGlassEffectView()
        rim.cornerRadius = corner
        if privateKeys {
            rim.setValue(11, forKey: "_variant")
            rim.contentView = glass
            if style == .liquid { return rim }
            // In one backdrop group the upper glass samples what is behind the window, not the glass under it.
            let group = UUID().uuidString
            for view in [base, glass, rim] { view.setValue(group, forKey: "_backdropGroupName") }
        }
        // Crystal is clear glass with a third of the rim over it. Frost is regular glass, as macOS draws its own
        // menus, lightened, with no rim. Graphite is regular glass darkened, with half of the rim.
        let stack = FillStack()
        var layers: [NSView] = [base]
        if let wash { layers.append(wash) }
        if privateKeys, style != .frost {
            rim.alphaValue = style == .graphite ? 0.5 : 0.33
            layers.append(rim)
        }
        for view in layers {
            view.autoresizingMask = [.width, .height]
            stack.addSubview(view)
        }
        return stack
    }
}

/// Layers of glass on top of each other, each as large as the stack. Autoresizing alone left a layer added at zero
/// size, like Graphite's dark wash, at zero size.
private final class FillStack: NSView {
    override func layout() {
        super.layout()
        for view in subviews where view.frame != bounds { view.frame = bounds }
    }
}

/// Scales the blur of the glass inside it. macOS draws glass with one fixed blur, a radius on a private filter of the
/// glass's backdrop layer, which this multiplies by `blur`. The layers appear only once the glass is on screen, and
/// macOS gives the filter its own radius back whenever it updates the glass, so each backdrop layer's filters are
/// observed and the radius set again. Where the filter is missing the glass stays as macOS draws it.
private final class BlurTunedView: NSView {
    var blur = 1.0 { didSet { if blur != oldValue { apply() } } }
    /// The radius given to glass that has no blur of its own, so `blur` has something to scale. 0 leaves it clear.
    var floor = 0.0
    /// Each filter input's own value, read before the first change.
    private var radii: [Input: Double] = [:]
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// The blur inputs of the glass's filter, the second one a wider, fainter blur under the first, and the classic
    /// material's.
    private static let inputs = ["glassBackground": ["inputBlurRadius", "inputBlurFillBlurRadius"], "gaussianBlur": ["inputRadius"]]

    private struct Input: Hashable {
        let layer: ObjectIdentifier
        let name: String
    }

    override func layout() {
        super.layout()
        apply()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The glass builds its layers after it is first shown.
        for delay in [0, 0.05, 0.3] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() } }
    }

    private func apply() {
        guard blur < 1 || floor > 0 || !radii.isEmpty, let layer else { return }
        // No implicit animation: the blur would visibly ease from macOS's radius to this one.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tune(layer)
        CATransaction.commit()
    }

    private func tune(_ layer: CALayer) {
        if NSStringFromClass(type(of: layer)) == "CABackdropLayer" {
            for filter in layer.filters as? [NSObject] ?? [] {
                guard let name = filter.value(forKey: "name") as? String, let inputs = Self.inputs[name] else { continue }
                // A filter on a layer changes only through the layer's key path.
                func set(_ input: String, _ value: Double) {
                    guard let now = filter.value(forKey: input) as? Double, abs(now - value) > 0.001 else { return }
                    layer.setValue(value, forKeyPath: "filters.\(name).\(input)")
                }
                for input in inputs {
                    guard let radius = filter.value(forKey: input) as? Double else { continue }
                    let id = Input(layer: ObjectIdentifier(layer), name: input)
                    let own = radii[id] ?? radius
                    radii[id] = own
                    if own == 0, floor > 0, input == "inputBlurRadius" {
                        // Clear glass also has the blur's opacity at 0, across the pill.
                        for step in 0...3 { set("inputBlurOpacity\(step)", 1) }
                        set(input, floor * blur)
                    } else {
                        // Setting it only when it differs keeps the observation below from looping.
                        set(input, own * blur)
                    }
                }
                if observations[ObjectIdentifier(layer)] == nil {
                    // In the same pass as macOS's own change, so no frame shows its radius.
                    observations[ObjectIdentifier(layer)] = layer.observe(\.filters) { [weak self] _, _ in
                        guard Thread.isMainThread else { return DispatchQueue.main.async { self?.apply() } }
                        MainActor.assumeIsolated { self?.apply() }
                    }
                }
            }
        }
        layer.sublayers?.forEach(tune)
    }
}
