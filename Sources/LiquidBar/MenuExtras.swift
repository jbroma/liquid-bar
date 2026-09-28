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
        return AX.children(AX.attribute(app, "AXExtrasMenuBar").map { $0 as! AXUIElement })
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

/// The status items the bar covers, as a section of Control Center's dropdown. A click on one with a menu lists its
/// entries inline, one item at a time; on one without, it presses the item, so its window or popover opens.
struct MenuExtrasSection: View {
    let extras: [MenuExtra<AXUIElement>]
    @State private var expanded: AXUIElement?
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        if !extras.isEmpty {
            MenuSeparator()
            MenuSection(title: "Menu Bar Items")
            ForEach(Array(extras.enumerated()), id: \.offset) { _, extra in
                let open = expanded == extra.handle
                MenuButton {
                    guard extra.hasMenu else {
                        slot.dismiss()
                        return AX.pressLater(extra.handle)
                    }
                    withAnimation(spring) { expanded = open ? nil : extra.handle }
                } content: {
                    Image(nsImage: AppIcons.icon(extra.bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(extra.appName).lineLimit(1)
                    Spacer(minLength: 8)
                    if let label = extra.label { Text(label).foregroundStyle(secondary).lineLimit(1) }
                    if extra.hasMenu { Disclosure(open: open) }
                }
                if open { MenuEntries(item: extra.handle, path: []) }
            }
        }
    }
}

/// The entries of `item`'s menu at `path`, the titles of the submenus leading there, read when shown. A submenu
/// expands the same way one level deeper; any other entry is pressed in its app, and the dropdown closes.
private struct MenuEntries: View {
    let item: AXUIElement
    let path: [String]
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
                    if open { MenuEntries(item: item, path: path + [entry.title]) }
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

    /// Titles line up with the app names above, and each submenu level steps in further.
    private var indent: CGFloat { 26 + 14 * CGFloat(path.count) }
}

/// A chevron that turns down while its row is expanded.
private struct Disclosure: View {
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(secondary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }
}
