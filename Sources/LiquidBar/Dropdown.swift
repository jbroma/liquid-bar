import LiquidBarCore
import SwiftUI

/// The items that open a dropdown. A workspace's hangs left of the notch, the rest right of it.
enum Dropdown: Hashable {
    case nowPlaying, volume, wifi, battery, controlCenter, clock
    case workspace(String)

    /// The item's id in the `ExpansionSlot`: its widget name, or "workspace:<id>".
    init?(owner: String) {
        if owner.hasPrefix("workspace:") {
            self = .workspace(String(owner.dropFirst("workspace:".count)))
        } else if let item = [Dropdown.nowPlaying, .volume, .wifi, .battery, .controlCenter, .clock].first(where: { $0.owner == owner }) {
            self = item
        } else {
            return nil
        }
    }

    var owner: String {
        switch self {
        case .workspace(let id): "workspace:\(id)"
        default: "\(self)"
        }
    }

    var isLeft: Bool {
        if case .workspace = self { true } else { false }
    }

    var width: CGFloat {
        switch self {
        case .controlCenter: 320
        case .clock: 276
        case .nowPlaying: 280
        case .workspace: 220
        default: 264
        }
    }
}

/// The black menu that flows down out of the bar under the open item: one shape with the bar, joined by concave
/// fillets. Each side of the notch has its own transparent window below the bar, whose clear pixels pass the pointer
/// through, and shows only its side's dropdowns. Moving to another item morphs it there; its content cross-fades.
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

    static let fillet: CGFloat = 10
    static let corner: CGFloat = 18

    private struct Geometry: Equatable {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    var body: some View {
        let open = slot.owner.flatMap(Dropdown.init(owner:)).flatMap { $0.isLeft == left && hasContent($0) ? $0 : nil }
        let pill = open.flatMap { slot.frames[$0.owner] } ?? anchor
        GeometryReader { proxy in
            let geometry = geometry(open, pill: pill, panelWidth: proxy.size.width)
            let shape = DropdownShape(fillet: Self.fillet, corner: Self.corner)
            shape
                .fill(.black)
                .frame(width: geometry.width + 2 * Self.fillet, height: geometry.height)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        if let open {
                            content(open)
                                .frame(width: open.width)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[open] = $0 }
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
                .offset(x: geometry.x - Self.fillet)
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

    private func geometry(_ open: Dropdown?, pill: CGRect, panelWidth: CGFloat) -> Geometry {
        guard let open, let height = heights[open] else { return Geometry(x: pill.minX - originX, width: pill.width, height: 0) }
        // Clear of the notch, and a few points in from the screen edge.
        let x = dropdownX(center: pill.midX - originX, width: open.width, lower: Self.fillet + (left ? 4 : 0), upper: panelWidth - Self.fillet - (left ? 0 : 4))
        return Geometry(x: x, width: open.width, height: height)
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

/// A body `2 * fillet` narrower than its rect hanging from a full-width top edge, joined to it by concave quarter
/// circles, with rounded bottom corners.
struct DropdownShape: Shape {
    let fillet: CGFloat
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        guard rect.height > 0.5 else { return Path() }
        let f = min(fillet, rect.height / 2)
        let left = rect.minX + fillet
        let right = rect.maxX - fillet
        let c = min(corner, rect.height - f, (right - left) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + fillet - f, y: rect.minY))
        path.addLine(to: CGPoint(x: right + f, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: right, y: rect.minY + f), radius: f)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.maxY), radius: c)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.minY), radius: c)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left - f, y: rect.minY), radius: f)
        path.closeSubpath()
        return path
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

/// A row that does something on click, with the native menus' rounded hover highlight.
struct MenuButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        MenuRow(content: content)
            .background { RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hovering ? 0.12 : 0)) }
            .contentShape(RoundedRectangle(cornerRadius: 7))
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
        MenuButton { shell("open 'x-apple.systempreferences:\(pane)'") } content: { Text(title) }
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
            MenuTitle(title: "Workspace \(id)")
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
