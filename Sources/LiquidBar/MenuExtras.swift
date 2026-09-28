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
        Task.detached {
            nonisolated(unsafe) let extras = trayItems(apps.flatMap { app in
                items(pid: app.pid).map { item in
                    var origin = CGPoint.zero
                    if let position = AX.attribute(item, kAXPositionAttribute) { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
                    return MenuExtra(bundleID: app.bundleID, appName: app.name, title: AX.string(item, kAXTitleAttribute),
                                     description: AX.string(item, kAXDescriptionAttribute), x: origin.x, handle: item)
                }
            })
            await MainActor.run { if extras != model.menuExtras { model.menuExtras = extras } }
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

/// The status items the bar covers, as a section of Control Center's dropdown. A click presses one, so its own menu
/// opens.
struct MenuExtrasSection: View {
    let extras: [MenuExtra<AXUIElement>]
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        if !extras.isEmpty {
            MenuSeparator()
            MenuSection(title: "Menu Bar Items")
            ForEach(Array(extras.enumerated()), id: \.offset) { _, extra in
                MenuButton {
                    slot.dismiss()
                    AX.pressLater(extra.handle)
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
    }
}
