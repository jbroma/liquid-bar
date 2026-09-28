import LiquidBarCore
import SwiftUI

/// The items that open a dropdown, and the ids of the `ExpansionSlot`. A workspace's hangs left of the notch, the rest
/// right of it.
nonisolated enum Dropdown: Hashable, Sendable {
    case nowPlaying, volume, wifi, battery, controlCenter, clock
    case workspace(String)

    var isLeft: Bool {
        if case .workspace = self { true } else { false }
    }

    var width: CGFloat {
        switch self {
        case .controlCenter: 280
        case .clock: 276
        case .nowPlaying: 280
        case .workspace: 220
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
    @State private var heights: [Dropdown: CGFloat] = [:]
    /// The pill the dropdown last hung from, where it shrinks back into while closing.
    @State private var anchor = CGRect.zero

    static let corner: CGFloat = 22
    /// The lit edge, brightest along the top like the pills' glint.
    static let rim = LinearGradient(stops: [.init(color: .white.opacity(0.35), location: 0), .init(color: .white.opacity(0.08), location: 0.5),
                                            .init(color: .white.opacity(0.14), location: 1)], startPoint: .top, endPoint: .bottom)

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
            let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
            Color.clear
                .glassEffect(.clear, in: shape)
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
                .overlay { shape.strokeBorder(Self.rim, lineWidth: 1).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
                .contentShape(shape)
                // SwiftUI can miss the exit when the dropdown closes under a still pointer, and then never reports
                // the next entry; every move inside reports it again.
                .onContinuousHover { phase in
                    if case .active = phase { slot.hold(true) } else { slot.hold(false) }
                }
                .offset(x: geometry.x, y: 6)
                .animation(spring, value: geometry)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
        .onChange(of: pill) { if open != nil { anchor = pill } }
    }

    /// A workspace with one app or none has nothing to list.
    private func hasContent(_ dropdown: Dropdown) -> Bool {
        if case .workspace(let id) = dropdown { model.workspaces.apps(on: id).count > 1 } else { true }
    }

    private func geometry(_ open: Dropdown?, pill: CGRect, panel: CGSize) -> Geometry {
        guard let open, let height = heights[open] else { return Geometry(x: pill.minX - originX, width: pill.width, height: 0) }
        // Clear of the notch, and a few points in from the screen edges.
        let x = dropdownX(center: pill.midX - originX, width: open.width, lower: left ? 14 : 10, upper: panel.width - (left ? 10 : 14))
        return Geometry(x: x, width: open.width, height: min(height, panel.height - 8))
    }

    @ViewBuilder private func content(_ dropdown: Dropdown) -> some View {
        switch dropdown {
        case .volume: VolumeMenu(model: model)
        case .wifi: NetworkMenu(network: model.network)
        case .battery: BatteryMenu(battery: model.battery)
        case .controlCenter: ControlCenterMenu(model: model)
        case .clock: ClockMenu(now: model.now)
        case .workspace(let id): WorkspaceMenu(model: model, id: id)
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

    /// A symbol's circle, filled white while `on`, like the controls in Control Center.
    func iconCircle(on: Bool, size: CGFloat) -> some View {
        foregroundStyle(on ? Color.black : Color.barWhite)
            .frame(width: size, height: size)
            .background(Circle().fill(on ? Color.barWhite : .white.opacity(0.14)))
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
