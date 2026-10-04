import AppKit
import LiquidBarCore
import SwiftUI

/// The native Apple menu, which is otherwise unreachable while the bar covers the menu bar. App Store's pending
/// updates and Recent Items are read from the real menu through Accessibility when the dropdown opens, and pressed
/// there; without access the dropdown leaves them out. Recent Items and Force Quit unfold inline, one at a time, and
/// the dropdown opens with both folded.
struct AppleMenu: View {
    @Environment(ExpansionSlot.self) private var slot
    @State private var unfolded: Fold?
    @State private var native = NativeAppleMenu()

    private enum Fold { case recent, forceQuit }

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
                fold(.recent, "Recent Items")
                if unfolded == .recent { recentItems }
            }
            MenuSeparator()
            fold(.forceQuit, "Force Quit", shortcut: MenuShortcut(key: "⎋", modifiers: [.option, .command]))
            if unfolded == .forceQuit { forceQuitApps }
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
        // SwiftUI can keep this view's state from one opening to the next; each opens folded and reads afresh.
        .onChange(of: slot.owner == .apple) { _, open in if !open { unfolded = nil } }
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

    private func fold(_ fold: Fold, _ title: String, shortcut: MenuShortcut? = nil) -> some View {
        MenuButton { withAnimation(spring) { unfolded = unfolded == fold ? nil : fold } } content: {
            icon(symbol: nil, image: nil)
            Text(title)
            Spacer(minLength: 8)
            if let shortcut, unfolded != fold { Text(shortcut.text).foregroundStyle(secondary) }
            Disclosure(open: unfolded == fold)
        }
    }

    @ViewBuilder private func icon(symbol: String?, image: NSImage?) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable() } else if let symbol { Image(systemName: symbol).foregroundStyle(secondary) }
        }
        .frame(width: 16, height: 16)
    }

    /// The real menu's Recent Items: its section titles, then each item with its icon.
    @ViewBuilder private var recentItems: some View {
        ForEach(Array(native.recent.enumerated()), id: \.offset) { _, item in
            switch item {
            case .section(let title):
                MenuSection(title: title).padding(.leading, 14)
            case .item(let entry, let icon, let symbol):
                row(entry.title.hasSuffix(".app") ? String(entry.title.dropLast(4)) : entry.title, symbol: symbol, image: icon, indent: 14) {
                    AX.pressLater(entry.handle)
                }
            case .clear(let entry):
                MenuSeparator().padding(.leading, 14)
                row(entry.title, indent: 14) { AX.pressLater(entry.handle) }
            }
        }
    }

    /// The system Force Quit window can only be opened by synthesizing ⌥⌘⎋, which needs Accessibility access.
    /// Listing apps and force-terminating them needs no permission.
    @ViewBuilder private var forceQuitApps: some View {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        ForEach(apps, id: \.processIdentifier) { app in
            row(app.localizedName ?? app.bundleIdentifier ?? "?", image: app.icon, indent: 14) { app.forceTerminate() }
        }
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
        /// An app's icon, or else the symbol for its section's kind of item.
        case item(MenuEntry<AXUIElement>, icon: NSImage?, symbol: String)
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
        menu.recent = AX.entries(submenu).compactMap { $0 }.filter { !$0.title.hasPrefix("Show “") }.map { entry in
            guard entry.enabled else {
                section = entry.title
                return .section(entry.title)
            }
            if entry.title == "Clear Menu" { return .clear(entry) }
            let symbol = section == "Servers" ? "externaldrive" : entry.title.dropFirst().contains(".") ? "doc" : "folder"
            return .item(entry, icon: icon(entry.title), symbol: symbol)
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
