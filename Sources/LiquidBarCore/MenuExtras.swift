import Foundation

/// A status item another app put in the native menu bar, which the bar covers. `Handle` is what presses it.
public struct MenuExtra<Handle> {
    public var bundleID: String
    public var appName: String
    /// The item's own title or description, when it sets a non-empty one.
    public var label: String?
    /// Its left edge in the native menu bar.
    public var x: Double
    /// It holds a menu, which the tray lists inline. Without one, pressing it opens a window or popover.
    public var hasMenu: Bool
    public var handle: Handle

    public init(bundleID: String, appName: String, title: String?, description: String?, x: Double, hasMenu: Bool, handle: Handle) {
        self.bundleID = bundleID
        self.appName = appName
        self.label = [title, description].compactMap { $0 }.first { !$0.isEmpty }
        self.x = x
        self.hasMenu = hasMenu
        self.handle = handle
    }
}

extension MenuExtra: Equatable where Handle: Equatable {}
extension MenuExtra: Sendable where Handle: Sendable {}

/// The tray's rows, in the native menu bar's left-to-right order. Apple's items, which the bar replaces, and
/// AeroSpace's, whose workspace the bar shows, are left out.
public func trayItems<Handle>(_ extras: [MenuExtra<Handle>]) -> [MenuExtra<Handle>] {
    extras.filter { !$0.bundleID.hasPrefix("com.apple.") && $0.bundleID != "bobko.aerospace" }.sorted { $0.x < $1.x }
}

/// One entry of another app's menu, read through Accessibility. `handle` presses it and `submenu` holds the entries it
/// opens.
public struct MenuEntry<Handle> {
    public var title: String
    public var enabled: Bool
    public var shortcut: MenuShortcut?
    public var checked: Bool
    public var submenu: Handle?
    public var handle: Handle

    public init(title: String, enabled: Bool, shortcut: MenuShortcut?, checked: Bool, submenu: Handle?, handle: Handle) {
        self.title = title
        self.enabled = enabled
        self.shortcut = shortcut
        self.checked = checked
        self.submenu = submenu
        self.handle = handle
    }
}

extension MenuEntry: Equatable where Handle: Equatable {}

/// A menu entry's key equivalent, as AppKit takes it: a lowercase key and its modifier keys.
public struct MenuShortcut: Equatable, Sendable {
    public var key: String
    public var modifiers: ShortcutModifiers

    public init(key: String, modifiers: ShortcutModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// "⇧⌘N", as a menu shows it.
    public var text: String {
        let glyphs = [(ShortcutModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined() + (key == " " ? "Space" : key.uppercased())
    }
}

/// The entries of `menu`, with nil for a separator, from each item's Accessibility attributes and children (an item's
/// first child is its submenu). An untitled item with a submenu, which some apps use for a custom view, contributes
/// that submenu's entries in its place. Separators at either end or next to another are left out, as NSMenu hides them.
public func menuEntries<Handle>(of menu: Handle, attribute: (Handle, String) -> Any?, children: (Handle) -> [Handle]) -> [MenuEntry<Handle>?] {
    func entries(_ menu: Handle) -> [MenuEntry<Handle>?] {
        children(menu).flatMap { item -> [MenuEntry<Handle>?] in
            let title = attribute(item, "AXTitle") as? String ?? ""
            let submenu = children(item).first
            guard !title.isEmpty else { return submenu.map(entries) ?? [nil] }
            let key = (attribute(item, "AXMenuItemCmdChar") as? String)?.lowercased() ?? ""
            let modifiers = ShortcutModifiers(axMask: attribute(item, "AXMenuItemCmdModifiers") as? Int ?? 0)
            return [MenuEntry(
                title: title,
                enabled: attribute(item, "AXEnabled") as? Bool ?? true,
                shortcut: key.isEmpty ? nil : MenuShortcut(key: key, modifiers: modifiers),
                checked: (attribute(item, "AXMenuItemMarkChar") as? String)?.isEmpty == false,
                submenu: submenu,
                handle: item)]
        }
    }
    let tidy = entries(menu).reduce(into: [MenuEntry<Handle>?]()) { tidy, entry in
        if entry != nil || tidy.last.map({ $0 != nil }) == true { tidy.append(entry) }
    }
    return tidy.last.map { $0 == nil } == true ? tidy.dropLast() : tidy
}
