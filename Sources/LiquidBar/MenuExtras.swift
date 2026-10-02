import AppKit
import SwiftUI
import ApplicationServices
import LiquidBarCore

/// Status items in the native menu bar, which the bar covers. Accessibility can still press them, and their menus
/// and panels open above the bar.
enum MenuExtras {
    nonisolated static func items(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        // A busy app would otherwise stall the caller for AX's default 6s.
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Since macOS 27, MenuBarAgent wraps each of Apple's items in a group; the item inside has the identifier and presses.
        return AX.children(AX.attribute(app, "AXExtrasMenuBar").map { $0 as! AXUIElement }).map { item in
            AX.string(item, kAXRoleAttribute) == kAXGroupRole ? AX.children(item).first ?? item : item
        }
    }

    /// Re-reads every app's status items into `model.menuExtras`. Asking some 40 apps takes most of a second, so it
    /// runs off the main thread.
    static func refresh(_ model: BarModel) {
        guard AXIsProcessTrusted() else { return }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { (pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "") }
        Task {
            let extras = await blocking { trayItems(apps.flatMap { app in
                items(pid: app.pid).map { item in
                    var origin = CGPoint.zero
                    if let position = AX.attribute(item, kAXPositionAttribute) { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
                    return MenuExtra(bundleID: app.bundleID, appName: app.name, title: AX.string(item, kAXTitleAttribute),
                                     description: AX.string(item, kAXDescriptionAttribute), x: origin.x,
                                     hasMenu: !AX.children(item).isEmpty, handle: item)
                }
            }) }
            if extras != model.menuExtras { model.menuExtras = extras }
        }
    }

    /// The entries of `item`'s menu at `path`, the titles of the submenus leading there. It walks from the item each
    /// time because some apps rebuild their menus within a second, which invalidates the elements read before.
    nonisolated static func entries(of item: AXUIElement, at path: [String]) -> [MenuEntry<AXUIElement>?] {
        path.reduce(AX.children(item).first.map(AX.entries) ?? []) { level, title in
            level.lazy.compactMap { $0 }.first { $0.title == title }?.submenu.map(AX.entries) ?? []
        }
    }

    /// Presses the entry `title` at `path` off the main thread, which the press blocks until the app handles it.
    static func press(_ item: AXUIElement, at path: [String], title: String) {
        DispatchQueue.global().async {
            if let entry = entries(of: item, at: path).lazy.compactMap({ $0 }).first(where: { $0.title == title }) {
                AX.press(entry.handle)
            }
        }
    }
}

/// Apps add their status items just after they finish launching, and lose them when they quit.
final class MenuExtrasSource {
    init(model: BarModel) {
        MenuExtras.refresh(model)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    MenuExtras.refresh(model)
                }
            }
        }
    }
}

/// The status items the bar covers, as a module of Control Center's dropdown that opens collapsed. A click on an item
/// with a menu lists its entries inline, one item at a time; on one without, it presses the item, so its window or
/// popover opens. The pin at a row's start moves the item onto the bar.
struct MenuExtrasSection: View {
    let model: BarModel
    @State private var shown = false
    @State private var expanded: AXUIElement?
    @State private var hovered: AXUIElement?
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        if !AXIsProcessTrusted() {
            MenuSeparator()
            MenuButton { Permission.accessibility.request() } content: { Text("Allow Access to Menu Bar Items…").lineLimit(1) }
                .frame(minHeight: 30)
        } else if !model.menuExtras.isEmpty {
            VStack(spacing: 0) {
                MenuSeparator()
                HeaderRow(title: "Menu Bar Items") {
                    Text("\(model.menuExtras.count)").foregroundStyle(secondary).monospacedDigit()
                    Disclosure(open: shown)
                }
                .hoverButton {
                    withAnimation(spring) { shown.toggle() }
                    if shown { delegate.access.did(.pin) }
                }
                if shown {
                    ForEach(Array(model.menuExtras.enumerated()), id: \.offset) { _, extra in row(extra) }
                        .transition(.opacity)
                }
            }
            .onChange(of: slot.owner == .controlCenter) { _, open in if !open { (shown, expanded) = (false, nil) } }
        }
    }

    @ViewBuilder private func row(_ extra: MenuExtra<AXUIElement>) -> some View {
        let open = expanded == extra.handle
        let pinned = model.config.pinned.contains(extra.bundleID)
        MenuButton {
            guard extra.hasMenu else {
                slot.dismiss()
                return AX.pressLater(extra.handle)
            }
            withAnimation(spring) { expanded = open ? nil : extra.handle }
        } content: {
            // A process without a bundle id has nothing to pin by.
            let pinnable = !extra.bundleID.isEmpty
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 11))
                .foregroundStyle(pinned ? Color.barWhite : secondary)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
                .opacity(pinnable && (pinned || hovered == extra.handle) ? 1 : 0)
                .onTapGesture { Setting.pinned(extra.bundleID, !pinned).save() }
                .allowsHitTesting(pinnable)
                .help(pinned ? "Unpin from the Bar" : "Pin to the Bar")
            Image(nsImage: AppIcons.icon(extra.bundleID))
                .resizable()
                .frame(width: 18, height: 18)
            Text(extra.appName).lineLimit(1)
            Spacer(minLength: 8)
            if let label = extra.label { Text(label).foregroundStyle(secondary).lineLimit(1) }
            if extra.hasMenu { Disclosure(open: open) }
        }
        .onHover { if $0 { hovered = extra.handle } else if hovered == extra.handle { hovered = nil } }
        if open { MenuEntries(item: extra.handle, path: []) }
    }
}

/// A pinned status item's dropdown: its menu, listed like the rows of Control Center's section.
struct MenuExtraMenu: View {
    let extra: MenuExtra<AXUIElement>?

    var body: some View {
        MenuBody {
            if let extra {
                MenuTitle(title: extra.appName)
                MenuEntries(item: extra.handle, path: [], inset: 0)
            }
        }
    }
}

/// All pinned status items in one pill: each one's app icon and title is its own hover target, opening its menu
/// as the dropdown under it. An item without a menu presses the status item on a click instead.
struct PinnedGroup: View {
    let extras: [MenuExtra<AXUIElement>]
    @Environment(ExpansionSlot.self) private var slot
    @Environment(\.bar) private var bar

    var body: some View {
        HStack(spacing: 0) {
            ForEach(extras, id: \.bundleID) { extra in
                LivePill(id: .menuExtra(extra.bundleID), pulse: 0, gap: 0) { open in
                    HStack(spacing: 5) {
                        Image(nsImage: AppIcons.icon(extra.bundleID))
                            .resizable()
                            .frame(width: 16, height: 16)
                        if let title = extra.title { Text(title) }
                    }
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .frame(minHeight: bar.item)
                    .background { hoverFill(open) }
                }
                .onTapGesture {
                    guard !extra.hasMenu else { return }
                    slot.dismiss()
                    AX.pressLater(extra.handle)
                }
            }
        }
        .pill(height: bar.pill, padding: 4)
        .padding(.horizontal, itemGap / 2)
    }
}

/// The entries of `item`'s menu at `path`, the titles of the submenus leading there, read when shown. A submenu
/// expands the same way one level deeper; any other entry is pressed in its app, and the dropdown closes.
struct MenuEntries: View {
    let item: AXUIElement
    let path: [String]
    /// Where the top level's titles start; Control Center lines them up with its app names, after the pin and icon.
    var inset: CGFloat = 50
    @State private var entries: [MenuEntry<AXUIElement>?] = []
    @State private var expanded: String?
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        // A stack rather than a bare ForEach, which has no view to run the read while it is empty.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                if let entry {
                    let open = expanded == entry.title
                    MenuButton {
                        guard entry.submenu == nil else { return withAnimation(spring) { expanded = open ? nil : entry.title } }
                        slot.dismiss()
                        MenuExtras.press(item, at: path, title: entry.title)
                    } content: {
                        Text(entry.title).lineLimit(1)
                        Spacer(minLength: 8)
                        if let shortcut = entry.shortcut { Text(shortcut.text).foregroundStyle(secondary) }
                        if entry.checked { Image(systemName: "checkmark").fontWeight(.semibold) }
                        if entry.submenu != nil { Disclosure(open: open) }
                    }
                    .foregroundStyle(entry.enabled ? Color.barWhite : secondary)
                    .allowsHitTesting(entry.enabled)
                    .padding(.leading, indent)
                    if open { MenuEntries(item: item, path: path + [entry.title], inset: inset) }
                } else {
                    MenuSeparator().padding(.leading, indent)
                }
            }
        }
        .task {
            let read = await blocking { [item, path] in MenuExtras.entries(of: item, at: path) }
            withAnimation(spring) { entries = read }
        }
    }

    /// Each submenu level steps in further.
    private var indent: CGFloat { inset + 14 * CGFloat(path.count) }
}

/// A chevron that turns down while its row is expanded.
struct Disclosure: View {
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(secondary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }
}
