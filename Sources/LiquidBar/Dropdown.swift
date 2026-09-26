import LiquidBarCore
import SwiftUI

/// The items that open a dropdown, keyed by their widget name.
enum Dropdown: String {
    case nowPlaying, menuExtras, volume, wifi, battery, clock

    var width: CGFloat {
        switch self {
        case .clock: 276
        case .nowPlaying: 280
        case .menuExtras: 240
        default: 264
        }
    }
}

/// The black menu that flows down out of the bar under the open item: one shape with the bar, joined by concave
/// fillets. It lives in its own transparent window below the bar, whose clear pixels pass the pointer through.
/// Moving to another item morphs it there; its content cross-fades.
struct DropdownView: View {
    let model: BarModel
    /// This window's left edge in the bar window's coordinates.
    let originX: CGFloat
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
        let open = slot.owner.flatMap(Dropdown.init(rawValue:))
        let pill = open.flatMap { slot.frames[$0.rawValue] } ?? anchor
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
                .onHover { slot.hold($0) }
                .offset(x: geometry.x - Self.fillet)
                .animation(spring, value: geometry)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
        .onChange(of: pill) { if open != nil { anchor = pill } }
    }

    private func geometry(_ open: Dropdown?, pill: CGRect, panelWidth: CGFloat) -> Geometry {
        guard let open, let height = heights[open] else { return Geometry(x: pill.minX - originX, width: pill.width, height: 0) }
        // Clear of the notch on the left, and a few points in from the screen edge on the right.
        let x = dropdownX(center: pill.midX - originX, width: open.width, lower: Self.fillet, upper: panelWidth - Self.fillet - 4)
        return Geometry(x: x, width: open.width, height: height)
    }

    @ViewBuilder private func content(_ dropdown: Dropdown) -> some View {
        switch dropdown {
        case .volume: VolumeMenu(model: model)
        case .wifi: NetworkMenu(network: model.network)
        case .battery: BatteryMenu(battery: model.battery)
        case .clock: ClockMenu(now: model.now)
        case .menuExtras: MenuExtrasMenu(model: model)
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
