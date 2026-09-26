import AppKit
import ApplicationServices
import LiquidBarCore

// One boundary per subsystem behind the Control Center dropdown. Each reads nil and does nothing when this macOS
// lacks what it needs, so a missing private symbol costs a tile, never a crash.

/// The real Control Center's status items, pressed through Accessibility.
enum SystemControlCenter {
    static let controlCenter = "com.apple.menuextra.controlcenter"
    static let screenMirroring = "com.apple.menuextra.screen-mirroring"

    /// Control Center's status items by identifier, empty without Accessibility access.
    nonisolated static func extras() -> [String: AXUIElement] {
        guard AXIsProcessTrusted(), let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        else { return [:] }
        return Dictionary(MenuExtras.items(pid: pid).compactMap { item in AppMenus.string(item, "AXIdentifier").map { ($0, item) } }) { first, _ in first }
    }

    /// Opens the status item's own panel or menu. False when there is no such item or no Accessibility access.
    static func open(_ id: String) -> Bool {
        guard let item = extras()[id] else { return false }
        MenuExtras.press(item)
        return true
    }
}

enum AirDrop {
    static func mode() -> AirDropMode? {
        (CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String).flatMap(AirDropMode.init)
    }

    static func openWindow() {
        shell("open -b com.apple.finder.Open-AirDrop")
    }
}
