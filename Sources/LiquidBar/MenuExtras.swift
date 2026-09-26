import AppKit
import ApplicationServices

/// Status items in the native menu bar, which the bar covers. Accessibility can still press them, and their menus
/// and panels open above the bar.
enum MenuExtras {
    /// Opens the real Control Center, or closes it when it is open.
    static func toggleControlCenter(explainAt screenPoint: NSPoint) {
        guard AXIsProcessTrusted() else { return AppMenus.explainAccess("open Control Center", at: screenPoint) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
              let item = items(pid: app.processIdentifier).first(where: { AppMenus.string($0, "AXIdentifier") == "com.apple.menuextra.controlcenter" })
        else { return }
        press(item)
    }

    static func items(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        // A busy app would otherwise stall the caller for AX's default 6s.
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AppMenus.children(AppMenus.attribute(app, "AXExtrasMenuBar").map { $0 as! AXUIElement })
    }

    /// A status item's press returns only once the menu it opens closes, so it runs off the main thread.
    static func press(_ item: AXUIElement) {
        nonisolated(unsafe) let item = item
        Task.detached { AXUIElementPerformAction(item, kAXPressAction as CFString) }
    }
}
