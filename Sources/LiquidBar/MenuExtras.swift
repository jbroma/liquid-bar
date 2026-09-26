import AppKit
import SwiftUI
import ApplicationServices
import LiquidBarCore

/// Status items in the native menu bar, which the bar covers. Accessibility can still press them, and their menus
/// and panels open above the bar.
enum MenuExtras {
    /// Opens or closes the real Control Center. Its menu extra only toggles, so the current state is read from its
    /// panel window first.
    static func setControlCenter(open: Bool, explainAt screenPoint: NSPoint) {
        guard AXIsProcessTrusted() else {
            if open { AppMenus.explainAccess("open Control Center", at: screenPoint) }
            return
        }
        guard open != controlCenterIsOpen,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
              let item = items(pid: app.processIdentifier).first(where: { AppMenus.string($0, "AXIdentifier") == "com.apple.menuextra.controlcenter" })
        else { return }
        press(item)
    }

    /// Control Center's panel is its only tall window; its status items are 30pt strips.
    private static var controlCenterIsOpen: Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            window[kCGWindowOwnerName as String] as? String == "Control Center"
                && ((window[kCGWindowBounds as String] as? [String: Any])?["Height"] as? CGFloat ?? 0) > 100
        }
    }

    nonisolated static func items(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        // A busy app would otherwise stall the caller for AX's default 6s.
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AppMenus.children(AppMenus.attribute(app, "AXExtrasMenuBar").map { $0 as! AXUIElement })
    }

    /// Re-reads every app's status items into `model.menuExtras`. Asking some 40 apps takes most of a second, so it
    /// runs off the main thread.
    static func refresh(_ model: BarModel) {
        guard AXIsProcessTrusted() else { return }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { (pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "") }
        Task.detached {
            nonisolated(unsafe) let extras = trayItems(apps.flatMap { app in
                items(pid: app.pid).map { item in
                    var origin = CGPoint.zero
                    if let position = AppMenus.attribute(item, kAXPositionAttribute) { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
                    return MenuExtra(bundleID: app.bundleID, appName: app.name, title: AppMenus.string(item, kAXTitleAttribute),
                                     description: AppMenus.string(item, kAXDescriptionAttribute), x: origin.x, handle: item)
                }
            })
            await MainActor.run { if extras != model.menuExtras { model.menuExtras = extras } }
        }
    }

    /// A status item's press returns only once the menu it opens closes, so it runs off the main thread.
    static func press(_ item: AXUIElement) {
        nonisolated(unsafe) let item = item
        Task.detached { AXUIElementPerformAction(item, kAXPressAction as CFString) }
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

/// The status items the bar covers. A click presses one, so its own menu opens.
struct MenuExtrasMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        MenuBody {
            MenuTitle(title: "Menu Bar Items")
            ForEach(Array(model.menuExtras.enumerated()), id: \.offset) { _, extra in
                MenuButton {
                    slot.dismiss()
                    MenuExtras.press(extra.handle)
                } content: {
                    Image(nsImage: AppIcons.icon(extra.bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(extra.appName).lineLimit(1)
                    Spacer(minLength: 8)
                    if let label = extra.label { Text(label).foregroundStyle(secondary).lineLimit(1) }
                }
            }
        }
        .task { MenuExtras.refresh(model) }
    }
}
