import AppKit
import LiquidBarCore
import SwiftUI

/// The native Apple menu, which is otherwise unreachable while the bar covers the menu bar. App Store's pending
/// updates and Recent Items are read from the real menu through Accessibility when the dropdown opens, and pressed
/// there; without access the dropdown leaves them out. Recent Items and Force Quit open native submenus beside their
/// rows, as the Apple menu's do, which scroll when long.
struct AppleMenu: View {
    @Environment(ExpansionSlot.self) private var slot
    @State private var native = NativeAppleMenu()

    var body: some View {
        MenuBody {
            row("About This Mac", symbol: "laptopcomputer") { shell("open -a 'About This Mac'") }
            MenuSeparator()
            row("System Settings…", symbol: "gearshape") { shell("open -a 'System Settings'") }
            row("App Store…", symbol: "bag", badge: native.appStoreBadge) {
                if let entry = native.appStore { AX.pressLater(entry.handle) } else { shell("open -a 'App Store'") }
            }
            if !native.recent.isEmpty {
                MenuSeparator()
                SubmenuRow(title: "Recent Items") { [native] in native.recentMenu() }
            }
            MenuSeparator()
            SubmenuRow(title: "Force Quit", shortcut: MenuShortcut(key: "⎋", modifiers: [.option, .command])) { forceQuitMenu() }
            MenuSeparator()
            row("Sleep") { shell("pmset sleepnow") }
            // loginwindow's own confirmation dialogs (kAEShowRestartDialog, kAEShowShutdownDialog, kAELogOut).
            row("Restart…") { Permission.loginwindow.tell("«event aevtrrst»") }
            row("Shut Down…") { Permission.loginwindow.tell("«event aevtrsdn»") }
            MenuSeparator()
            row("Lock Screen", shortcut: MenuShortcut(key: "q", modifiers: [.control, .command])) { lockScreen() }
            row("Log Out \(NSFullUserName())…", shortcut: MenuShortcut(key: "q", modifiers: [.shift, .command])) {
                Permission.loginwindow.tell("«event aevtlogo»")
            }
        }
        // Read afresh at each opening.
        .task(id: slot.owner == .apple) {
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            let read = await blocking { NativeAppleMenu.read(pid: pid) }
            withAnimation(spring) { native = read }
        }
    }

    /// A row that closes the dropdown, then acts. The icon column is kept for every row, as in the native menu.
    private func row(_ title: String, symbol: String? = nil, image: NSImage? = nil, badge: String? = nil, shortcut: MenuShortcut? = nil,
                     indent: CGFloat = 0, _ action: @escaping () -> Void) -> some View {
        MenuButton {
            slot.dismiss()
            action()
        } content: {
            icon(symbol: symbol, image: image)
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if let badge { Badge(text: badge) }
            if let shortcut { Text(shortcut.text).foregroundStyle(secondary) }
        }
        .padding(.leading, indent)
    }

    @ViewBuilder private func icon(symbol: String?, image: NSImage?) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable() } else if let symbol { Image(systemName: symbol).foregroundStyle(secondary) }
        }
        .frame(width: 16, height: 16)
    }

    /// The running apps with their icons; picking one force-quits it. The system Force Quit window can only be opened
    /// by synthesizing ⌥⌘⎋, which needs Accessibility access, while listing apps and force-terminating them needs no
    /// permission.
    private func forceQuitMenu() -> NSMenu {
        let menu = NSMenu(title: "Force Quit")
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in apps {
            let item = actionItem(app.localizedName ?? app.bundleIdentifier ?? "?") { app.forceTerminate() }
            item.image = app.icon.map { sized($0) }
            menu.addItem(item)
        }
        return menu
    }

    private func lockScreen() {
        // The same private call the native "Lock Screen" item uses; there is no public API.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }
}

/// What the dropdown takes from the real Apple menu, which lives in the front app's menu bar.
nonisolated struct NativeAppleMenu: @unchecked Sendable {
    enum Recent {
        case section(String)
        /// An app's icon, or else the symbol for its section's kind of item, and its "Show … in Finder" for ⌘.
        case item(MenuEntry<AXUIElement>, icon: NSImage?, symbol: String, reveal: MenuEntry<AXUIElement>?)
        /// Clear Menu, set apart below the items.
        case clear(MenuEntry<AXUIElement>)
    }

    var appStore: MenuEntry<AXUIElement>?
    var recent: [Recent] = []

    /// "2 updates", from the App Store entry's title, "App Store…, 2 updates".
    var appStoreBadge: String? {
        appStore?.title.components(separatedBy: ", ").dropFirst().first
    }

    nonisolated static func read(pid: pid_t) -> NativeAppleMenu {
        guard AXIsProcessTrusted(), let bar = AX.attribute(AXUIElementCreateApplication(pid), "AXMenuBar"),
              let apple = AX.children((bar as! AXUIElement)).first
        else { return NativeAppleMenu() }
        let entries = AX.children(apple).first.map(AX.entries)?.compactMap { $0 } ?? []
        var menu = NativeAppleMenu()
        menu.appStore = entries.first { $0.title.hasPrefix("App Store") }
        guard let submenu = entries.first(where: { $0.submenu != nil && $0.title == "Recent Items" })?.submenu else { return menu }
        // Each item has a "Show … in Finder" alternate for ⌘, which the dropdown leaves out, as the menu shows it.
        var section = ""
        let items = AX.entries(submenu).compactMap { $0 }
        for (index, entry) in items.enumerated() where !entry.title.hasPrefix("Show “") {
            guard entry.enabled else {
                section = entry.title
                menu.recent.append(.section(entry.title))
                continue
            }
            if entry.title == "Clear Menu" {
                menu.recent.append(.clear(entry))
                continue
            }
            let symbol = section == "Servers" ? "externaldrive" : entry.title.dropFirst().contains(".") ? "doc" : "folder"
            let next = items.indices.contains(index + 1) ? items[index + 1] : nil
            menu.recent.append(.item(entry, icon: icon(entry.title), symbol: symbol, reveal: next.flatMap { $0.title.hasPrefix("Show “") ? $0 : nil }))
        }
        return menu
    }

    /// Recent Items as the Apple menu shows it: section headers, items with their icons, each with "Show … in Finder"
    /// while ⌘ is down, and Clear Menu.
    @MainActor func recentMenu() -> NSMenu {
        let menu = NSMenu(title: "Recent Items")
        for item in recent {
            switch item {
            case .section(let title):
                if menu.numberOfItems > 0 { menu.addItem(.separator()) }
                menu.addItem(.sectionHeader(title: title))
            case .item(let entry, let icon, let symbol, let reveal):
                let title = entry.title.hasSuffix(".app") ? String(entry.title.dropLast(4)) : entry.title
                let open = actionItem(title) { AX.pressLater(entry.handle) }
                open.image = icon.map { sized($0) } ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                open.keyEquivalentModifierMask = []
                menu.addItem(open)
                if let reveal {
                    let show = actionItem(reveal.title) { AX.pressLater(reveal.handle) }
                    show.keyEquivalentModifierMask = .command
                    show.isAlternate = true
                    menu.addItem(show)
                }
            case .clear(let entry):
                menu.addItem(.separator())
                menu.addItem(actionItem(entry.title) { AX.pressLater(entry.handle) })
            }
        }
        return menu
    }

    /// An app's own icon, found where apps live; other items get none.
    private nonisolated static func icon(_ title: String) -> NSImage? {
        guard title.hasSuffix(".app") else { return nil }
        let path = ["/Applications", "/System/Applications", "/Applications/Utilities", "/System/Applications/Utilities"]
            .map { "\($0)/\(title)" }
            .first { FileManager.default.fileExists(atPath: $0) }
        return path.map { NSWorkspace.shared.icon(forFile: $0) }
    }
}

/// A small capsule, like the App Store's update count.
private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(.white.opacity(0.14)))
    }
}

/// An icon at a menu item's size.
private func sized(_ image: NSImage) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.size = NSSize(width: 16, height: 16)
    return copy
}

/// A row that opens a native submenu beside the dropdown, as the Apple menu's rows with a chevron do: when the pointer
/// rests on it, or on a click. The submenu is built when it opens, so it is current.
private struct SubmenuRow: View {
    let title: String
    var shortcut: MenuShortcut?
    let menu: () -> NSMenu
    @State private var anchor = Anchor()
    @State private var hovering = false

    var body: some View {
        MenuButton(action: open) {
            Text(title)
            Spacer(minLength: 8)
            if let shortcut { Text(shortcut.text).foregroundStyle(secondary) }
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary)
        }
        .background { AnchorView(anchor: anchor) }
        .onHover { hovering = $0 }
        .task(id: hovering) {
            guard hovering else { return }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { open() }
        }
    }

    /// Pops the menu up with its first item level with the row, just past the dropdown's right edge.
    private func open() {
        guard let view = anchor.view, let window = view.window else { return }
        let row = window.convertToScreen(view.convert(view.bounds, to: nil))
        menu().popUp(positioning: nil, at: NSPoint(x: row.maxX + 14, y: row.maxY), in: nil)
    }
}

/// The AppKit view behind a row, which knows where the row is on screen.
private final class Anchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: Anchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
