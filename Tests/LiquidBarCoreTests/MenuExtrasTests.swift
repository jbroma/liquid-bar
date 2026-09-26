import LiquidBarCore
import Testing

private func extra(_ bundleID: String, _ name: String, title: String? = nil, description: String? = nil, x: Double) -> MenuExtra<Int> {
    MenuExtra(bundleID: bundleID, appName: name, title: title, description: description, x: x, handle: Int(x))
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
