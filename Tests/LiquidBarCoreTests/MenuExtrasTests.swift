import LiquidBarCore
import Testing

private func extra(_ bundleID: String, _ name: String, title: String? = nil, description: String? = nil, x: Double) -> MenuExtra<Int> {
    MenuExtra(bundleID: bundleID, appName: name, title: title, description: description, x: x, hasMenu: true, handle: Int(x))
}

@Test func trayListsThirdPartyItemsLeftToRight() {
    // What this Mac's apps expose through AXExtrasMenuBar.
    let extras = [
        extra("com.apple.controlcenter", "Control Center", description: "Battery", x: 1325),
        extra("com.example.containers", "Containers", title: "", x: 1248),
        extra("com.example.vault", "Vault", title: "", x: 1208),
        extra("bobko.aerospace", "AeroSpace", title: "1", x: 1183),
        extra("com.example.launcher", "Launcher", title: "", x: 1151),
    ]
    let tray = trayItems(extras)
    #expect(tray.map(\.appName) == ["Launcher", "Vault", "Containers"])
    #expect(tray.map(\.handle) == [1151, 1208, 1248])
}

@Test func labelIsTheFirstNonEmptyTitleOrDescription() {
    #expect(extra("a", "A", title: "", x: 0).label == nil)
    #expect(extra("a", "A", title: "", description: "VPN on", x: 0).label == "VPN on")
    #expect(extra("a", "A", title: "12°", description: "Weather", x: 0).label == "12°")
    #expect(extra("a", "A", x: 0).label == nil)
}

@Test func menuEntriesFromAccessibilityAttributes() {
    // Containers's status menu, trimmed: a doubled separator, an untitled item holding a custom view's rows, a submenu.
    let children: [String: [String]] = [
        "menu": ["open", "sep1", "sep2", "running", "view", "sep3", "help", "quit", "sep4"],
        "view": ["viewMenu"],
        "viewMenu": ["sep5", "dev"],
        "help": ["helpMenu"],
        "helpMenu": ["docs"],
    ]
    let attributes: [String: [String: Any]] = [
        "open": ["AXTitle": "Open Containers", "AXEnabled": true, "AXMenuItemCmdChar": "n", "AXMenuItemCmdModifiers": 0],
        "sep1": ["AXTitle": "", "AXEnabled": false],
        "sep2": ["AXTitle": "", "AXEnabled": false],
        "running": ["AXTitle": "None running", "AXEnabled": false],
        "view": ["AXTitle": ""],
        "sep5": ["AXTitle": "", "AXEnabled": false],
        "dev": ["AXTitle": "dev", "AXEnabled": true, "AXMenuItemMarkChar": "✓"],
        "sep3": ["AXTitle": "", "AXEnabled": false],
        "help": ["AXTitle": "Help", "AXEnabled": true],
        "quit": ["AXTitle": "Quit", "AXEnabled": true, "AXMenuItemCmdChar": " ", "AXMenuItemCmdModifiers": 3],
        "sep4": ["AXTitle": "", "AXEnabled": false],
    ]
    let entries = menuEntries(of: "menu", attribute: { attributes[$0]?[$1] }, children: { children[$0] ?? [] })
    #expect(entries == [
        MenuEntry(title: "Open Containers", enabled: true, shortcut: MenuShortcut(key: "n", modifiers: .command), checked: false, submenu: nil, handle: "open"),
        nil,
        MenuEntry(title: "None running", enabled: false, shortcut: nil, checked: false, submenu: nil, handle: "running"),
        nil,
        MenuEntry(title: "dev", enabled: true, shortcut: nil, checked: true, submenu: nil, handle: "dev"),
        nil,
        MenuEntry(title: "Help", enabled: true, shortcut: nil, checked: false, submenu: "helpMenu", handle: "help"),
        MenuEntry(title: "Quit", enabled: true, shortcut: MenuShortcut(key: " ", modifiers: [.command, .shift, .option]), checked: false, submenu: nil, handle: "quit"),
    ])
}

@Test func shortcutTextUsesTheMenuGlyphOrder() {
    #expect(MenuShortcut(key: "n", modifiers: .command).text == "⌘N")
    #expect(MenuShortcut(key: " ", modifiers: [.command, .shift, .option, .control]).text == "⌃⌥⇧⌘Space")
}
