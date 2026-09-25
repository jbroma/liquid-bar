import AppKit
import ApplicationServices
import LiquidBarCore
import SwiftUI

/// One top-level menu of the front app (File, Edit, …), read through the Accessibility API.
struct AppMenuTitle: Identifiable {
    let id: Int
    let title: String
    let element: AXUIElement
}

/// The front app's menus, which the covered native menu bar would otherwise hide.
enum AppMenus {
    /// Top-level menu titles after the Apple menu, or nil without Accessibility access.
    static func titles(pid: pid_t) -> [AppMenuTitle]? {
        guard AXIsProcessTrusted() else { return nil }
        let items = children(attribute(AXUIElementCreateApplication(pid), kAXMenuBarAttribute).map { $0 as! AXUIElement })
        return items.dropFirst().enumerated().compactMap { index, item in
            guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { return nil }
            return AppMenuTitle(id: index, title: title, element: item)
        }
    }

    /// Opens a native dropdown mirroring the menu bar item's menu; picking an item presses it in the app.
    static func popUp(_ title: AppMenuTitle, at screenPoint: NSPoint) {
        guard let menu = children(title.element).first else { return }
        fillers = []
        mirror(menu, title: title.title).popUp(positioning: nil, at: screenPoint, in: nil)
    }

    /// Explains the missing permission instead of the menus, and offers the Privacy pane.
    static func explainAccess(appName: String, at screenPoint: NSPoint) {
        let menu = NSMenu()
        let explanation = NSMenuItem(title: "LiquidBar needs Accessibility access to show \(appName)'s menus.", action: nil, keyEquivalent: "")
        explanation.isEnabled = false
        menu.addItem(explanation)
        menu.addItem(actionItem("Open Accessibility Settings…") {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
        })
        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    /// NSMenu holds its delegate weakly; the fillers of the open menu tree live here until the next popup.
    private static var fillers: [MenuFiller] = []

    fileprivate static func mirror(_ element: AXUIElement, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        let filler = MenuFiller(element: element)
        fillers.append(filler)
        menu.delegate = filler
        return menu
    }

    fileprivate static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    fileprivate static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    fileprivate static func children(_ element: AXUIElement?) -> [AXUIElement] {
        element.flatMap { attribute($0, kAXChildrenAttribute) as? [AXUIElement] } ?? []
    }
}

/// Fills an NSMenu from an AX menu only when it opens, so deep menus cost nothing until shown.
private final class MenuFiller: NSObject, NSMenuDelegate {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for child in AppMenus.children(element) {
            let title = AppMenus.string(child, kAXTitleAttribute) ?? ""
            let submenu = AppMenus.children(child).first
            guard !title.isEmpty || submenu != nil else {
                menu.addItem(.separator())
                continue
            }
            let item = actionItem(title) { AXUIElementPerformAction(child, kAXPressAction as CFString) }
            item.isEnabled = AppMenus.attribute(child, kAXEnabledAttribute) as? Bool ?? true
            if AppMenus.string(child, kAXMenuItemMarkCharAttribute)?.isEmpty == false { item.state = .on }
            if let key = AppMenus.string(child, kAXMenuItemCmdCharAttribute), !key.isEmpty {
                item.keyEquivalent = key.lowercased()
                let modifiers = ShortcutModifiers(axMask: AppMenus.attribute(child, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0)
                item.keyEquivalentModifierMask = [
                    modifiers.contains(.command) ? .command : [],
                    modifiers.contains(.shift) || key != key.lowercased() ? .shift : [],
                    modifiers.contains(.option) ? .option : [],
                    modifiers.contains(.control) ? .control : [],
                ]
            }
            if let submenu {
                item.action = nil
                item.submenu = AppMenus.mirror(submenu, title: title)
            }
            menu.addItem(item)
        }
    }
}

/// Whether one bar's left island shows the front app's menu titles instead of the workspaces. Esc, clicking the
/// app again, or the pointer staying away for 1.5s morphs it back.
@Observable
final class MenuMode {
    private(set) var titles: [AppMenuTitle]?
    @ObservationIgnored private var leave: Task<Void, Never>?
    @ObservationIgnored private var escape: Any?
    @ObservationIgnored private var dropdownOpen = false
    @ObservationIgnored private var pointerInside = false

    var active: Bool { titles != nil }

    func toggle(_ app: FrontApp, at screenPoint: NSPoint) {
        if active { return end() }
        guard let titles = AppMenus.titles(pid: app.pid) else {
            return AppMenus.explainAccess(appName: app.name, at: screenPoint)
        }
        withAnimation(spring) { self.titles = titles }
        // Global key events need Accessibility access, which reading the menus already proved.
        escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func open(_ title: AppMenuTitle, at screenPoint: NSPoint) {
        dropdownOpen = true
        AppMenus.popUp(title, at: screenPoint)
        dropdownOpen = false
        if !pointerInside { hover(false) }
    }

    func hover(_ inside: Bool) {
        pointerInside = inside
        leave?.cancel()
        guard !inside, active else { return }
        leave = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !dropdownOpen else { return }
            end()
        }
    }

    func end() {
        leave?.cancel()
        escape.map(NSEvent.removeMonitor)
        escape = nil
        if active { withAnimation(spring) { titles = nil } }
    }
}
