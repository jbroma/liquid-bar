import LiquidBarCore
import SwiftUI

/// The items that open a dropdown, and the ids of the `ExpansionSlot`. The Apple logo's and a workspace's hang left of the notch, the rest
/// right of it.
nonisolated enum Dropdown: Hashable, Sendable {
    case nowPlaying, volume, wifi, battery, controlCenter, clock
    case apple
    case workspace(String)
    /// A pinned app's status item, by bundle id.
    case menuExtra(String)

    var isLeft: Bool {
        switch self {
        case .apple, .workspace: true
        default: false
        }
    }

    var width: CGFloat {
        switch self {
        case .controlCenter: 300
        case .clock: 276
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
    /// The pill the dropdown last hung from, where it shrinks back into while closing.
    @State private var anchor = CGRect.zero

    static let corner: CGFloat = 18

    private struct Geometry: Equatable {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    var body: some View {
        let open = slot.owner.flatMap { $0.isLeft == left && hasContent($0) ? $0 : nil }
        let pill = open.flatMap { slot.frames[$0] } ?? anchor
        GeometryReader { proxy in
            let geometry = geometry(open, pill: pill, panel: proxy.size)
            // In the bar's coordinates, reaching up over the gap to the bar so a pointer crossing it stays inside.
            let area = open.map { _ in CGRect(x: originX + geometry.x, y: bar.height, width: geometry.width, height: geometry.height + 6) }
            let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
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
                // Closed, the panel shrinks to a flat strip whose edge and shadow would still draw a line.
                .opacity(open == nil ? 0 : 1)
                .offset(x: geometry.x, y: 6)
                .animation(spring, value: geometry)
                .animation(.easeOut(duration: 0.18), value: open == nil)
                .onChange(of: area, initial: true) { slot.dropdowns[left] = area }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
        .onChange(of: pill) { if open != nil { anchor = pill } }
    }

    /// A workspace with one app or none has nothing to list, and neither has a status item without a menu.
    private func hasContent(_ dropdown: Dropdown) -> Bool {
        switch dropdown {
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
        case .controlCenter: ControlCenterMenu(model: model)
        case .clock: ClockMenu(now: model.now)
        case .apple: AppleMenu()
        case .workspace(let id): WorkspaceMenu(model: model, id: id)
        case .menuExtra(let id): MenuExtraMenu(extra: model.pinnedExtras.first { $0.bundleID == id })
        case .nowPlaying: NowPlayingMenu(nowPlaying: model.nowPlaying, artwork: model.artwork, control: model.control)
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

/// A title with a control at its end, as tall as a row in a Control Center module: the header of the Bluetooth and
/// AirDrop lists with their switches, or a switch row like "Show Percentage".
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

/// The dropdowns' and windows' glass in the config's style, or in `style` for a preview. It follows the config live.
struct OverlayGlass: View {
    let corner: CGFloat
    var style: GlassStyle?

    var body: some View {
        let shown = style ?? delegate.model.config.glassStyle
        StyledGlass(corner: corner, style: shown, preview: style != nil).id(shown)
    }
}

/// The fill of a bar pill or of the focused workspace, matching the style's dropdown glass. Liquid keeps the flat fill:
/// pills in the volume overlay's glass drew heavy white rims at bar height.
struct PillFill<S: Shape>: View {
    let shape: S
    var style: GlassStyle?

    var body: some View {
        let style = style ?? delegate.model.config.glassStyle
        if let blend = style.blend {
            shape.fill(.white.opacity(blend.pillFill))
            shape.stroke(.white.opacity(blend.pillOutline), lineWidth: 1)
        } else {
            switch style {
            case .frost: Color.clear.glassEffect(.regular, in: shape)
            case .mist: shape.fill(.white.opacity(0.26))
            default: shape.fill(.black.opacity(0.32))
            }
        }
    }
}

private struct StyledGlass: NSViewRepresentable {
    let corner: CGFloat
    let style: GlassStyle
    /// A preview blurs what its own window draws under it rather than what lies behind the window.
    let preview: Bool

    /// Liquid is the lit rim of the private variant 11 around regular glass, as macOS's volume overlay draws it, and
    /// Crystal is clear glass. Dew and Pearl fade Liquid over Crystal. Mist is the private light variant 6 with its
    /// scrim. Without the private setters, all but Crystal fall back to regular.
    /// Frost is the classic popover material, whose blur is far heavier than any Liquid Glass.
    func makeNSView(context: Context) -> NSView {
        if style == .frost {
            let frost = NSVisualEffectView()
            frost.material = .popover
            frost.blendingMode = preview ? .withinWindow : .behindWindow
            frost.state = .active
            frost.wantsLayer = true
            frost.layer?.cornerRadius = corner
            frost.layer?.cornerCurve = .continuous
            frost.layer?.masksToBounds = true
            return frost
        }
        let glass = NSGlassEffectView()
        glass.cornerRadius = corner
        let privateKeys = ["set_variant:", "set_scrimState:", "set_backdropGroupName:"].allSatisfy { glass.responds(to: Selector($0)) }
        if let blend = style.blend, privateKeys {
            let crystal = NSGlassEffectView()
            crystal.cornerRadius = corner
            crystal.style = .clear
            if blend.liquid == 0 { return crystal }
            let rim = NSGlassEffectView()
            rim.cornerRadius = corner
            rim.setValue(11, forKey: "_variant")
            rim.contentView = glass
            if blend.liquid == 1 { return rim }
            // In one backdrop group the upper glass samples what is behind the window, not the glass under it, so
            // its opacity crossfades the two looks evenly.
            let group = UUID().uuidString
            for view in [crystal, glass, rim] { view.setValue(group, forKey: "_backdropGroupName") }
            rim.alphaValue = blend.liquid
            let stack = NSView()
            for view in [crystal, rim] {
                view.autoresizingMask = [.width, .height]
                stack.addSubview(view)
            }
            return stack
        }
        switch style {
        case .mist where privateKeys:
            glass.setValue(6, forKey: "_variant")
            glass.setValue(1, forKey: "_scrimState")
        case .crystal:
            glass.style = .clear
        case .obsidian:
            glass.style = .clear
            glass.tintColor = .black.withAlphaComponent(0.55)
        default:
            break
        }
        return glass
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
