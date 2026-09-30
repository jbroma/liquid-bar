import AppKit
import ApplicationServices
import LiquidBarCore
import SwiftUI

extension NSMenu {
    /// Shows the menu with its top edge at `point` until it closes. `popUp(positioning: nil, at:)` puts the first item
    /// at the point, and the menu draws 4.5pt of padding above it. Any part above the screen's visible frame, whose
    /// top is the bar's bottom, makes AppKit scroll the menu and hide its first item.
    func popUp(below point: NSPoint) {
        popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y - 5), in: nil)
    }
}

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
        let items = AX.children(AX.attribute(AXUIElementCreateApplication(pid), kAXMenuBarAttribute).map { $0 as! AXUIElement })
        return items.dropFirst().enumerated().compactMap { index, item in
            guard let title = AX.string(item, kAXTitleAttribute), !title.isEmpty else { return nil }
            return AppMenuTitle(id: index, title: title, element: item)
        }
    }

    /// A native dropdown mirroring the menu bar item's menu; picking an item presses it in the app.
    static func menu(for title: AppMenuTitle) -> NSMenu? {
        AX.children(title.element).first.map { mirror($0, title: title.title) }
    }

    /// The menus that do not fit beside the notch, each as a submenu.
    static func overflowMenu(_ titles: [AppMenuTitle]) -> NSMenu {
        let menu = NSMenu()
        for title in titles {
            let item = NSMenuItem(title: title.title, action: nil, keyEquivalent: "")
            item.submenu = self.menu(for: title)
            menu.addItem(item)
        }
        return menu
    }

    /// Shows `menu` until it closes. Returns the column from `columnUnder` that the pointer slid onto, which closed the
    /// menu, if any.
    static func popUp(_ menu: NSMenu, at screenPoint: NSPoint, columnUnder: @escaping (NSPoint) -> Int?) -> Int? {
        defer { fillers = [] }
        let switcher = TitleSwitch(menu: menu, columnUnder: columnUnder)
        // A tracking menu hides the pointer from SwiftUI's hover, so poll it in the menu's run loop mode instead.
        let poll = Timer(timeInterval: 1.0 / 60, target: switcher, selector: #selector(TitleSwitch.poll), userInfo: nil, repeats: true)
        RunLoop.main.add(poll, forMode: .eventTracking)
        menu.popUp(below: screenPoint)
        poll.invalidate()
        return switcher.next
    }

    /// Explains the missing permission instead of doing `purpose`, and offers the Privacy pane.
    static func explainAccess(_ purpose: String, at screenPoint: NSPoint) {
        explain("LiquidBar needs Accessibility access to \(purpose).", fix: "Open Accessibility Settings…", at: screenPoint) {
            AccessWindow.requestAccess()
        }
    }

    static func explainDesktopShortcut(_ n: Int, at screenPoint: NSPoint) {
        explain(
            "Switching desktops needs the shortcut \"Switch to Desktop \(n)\" on, under Keyboard Shortcuts, Mission Control.",
            fix: "Open Keyboard Settings…", at: screenPoint
        ) {
            shell("open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'")
        }
    }

    private static func explain(_ text: String, fix: String, at screenPoint: NSPoint, action: @escaping () -> Void) {
        let menu = NSMenu()
        let explanation = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        explanation.isEnabled = false
        menu.addItem(explanation)
        menu.addItem(actionItem(fix, handler: action))
        menu.popUp(below: screenPoint)
    }

    /// NSMenu holds its delegate weakly; the fillers of the open menu tree live here until it closes.
    private static var fillers: [MenuFiller] = []

    fileprivate static func mirror(_ element: AXUIElement, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        let filler = MenuFiller(element: element)
        fillers.append(filler)
        menu.delegate = filler
        return menu
    }
}

/// A title in the strip: its full-height strip of the bar in screen coordinates, and the menu it opens.
struct MenuColumn {
    let id: Int
    let rect: CGRect
    let menu: () -> NSMenu?
}

/// Closes an open menu once the pointer is over another title, remembering that title.
private final class TitleSwitch: NSObject {
    let menu: NSMenu
    let columnUnder: (NSPoint) -> Int?
    var next: Int?

    init(menu: NSMenu, columnUnder: @escaping (NSPoint) -> Int?) {
        self.menu = menu
        self.columnUnder = columnUnder
    }

    @objc func poll() {
        guard next == nil, let column = columnUnder(NSEvent.mouseLocation) else { return }
        next = column
        menu.cancelTracking()
    }
}

/// Reads and presses other apps' UI elements through the Accessibility API.
enum AX {
    nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    nonisolated static func children(_ element: AXUIElement?) -> [AXUIElement] {
        element.flatMap { attribute($0, kAXChildrenAttribute) as? [AXUIElement] } ?? []
    }

    @discardableResult
    nonisolated static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// The entries of the menu `menu`, nil marking a separator.
    nonisolated static func entries(_ menu: AXUIElement) -> [MenuEntry<AXUIElement>?] {
        menuEntries(of: menu, attribute: { attribute($0, $1) }, children: { children($0) })
    }

    /// Presses without waiting: a press returns only once the menu or dialog it opens closes.
    static func pressLater(_ element: AXUIElement) {
        DispatchQueue.global().async { press(element) }
    }
}

/// An element is an immutable reference to another app's UI, which the Accessibility API takes from any thread.
extension AXUIElement: @retroactive @unchecked Sendable {}

/// Fills an NSMenu from an AX menu only when it opens, so deep menus cost nothing until shown.
private final class MenuFiller: NSObject, NSMenuDelegate {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in AX.entries(element) {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let item = actionItem(entry.title) { AX.pressLater(entry.handle) }
            item.isEnabled = entry.enabled
            if entry.checked { item.state = .on }
            if let shortcut = entry.shortcut {
                item.keyEquivalent = shortcut.key
                item.keyEquivalentModifierMask = [
                    shortcut.modifiers.contains(.command) ? .command : [],
                    shortcut.modifiers.contains(.shift) ? .shift : [],
                    shortcut.modifiers.contains(.option) ? .option : [],
                    shortcut.modifiers.contains(.control) ? .control : [],
                ]
            }
            if let submenu = entry.submenu {
                item.action = nil
                item.submenu = AppMenus.mirror(submenu, title: entry.title)
            }
            menu.addItem(item)
        }
    }
}

/// Whether one bar's left island shows the front app's menu titles instead of the workspaces. Esc, switching apps, or
/// the pointer leaving the bar morphs it back.
@Observable
final class MenuMode {
    private(set) var titles: [AppMenuTitle]?
    /// The title whose menu is open, highlighted in place of the pointer's, which SwiftUI stops following meanwhile.
    private(set) var openTitle: Int?
    @ObservationIgnored private var leave: Task<Void, Never>?
    @ObservationIgnored private var escape: Any?
    @ObservationIgnored private var dropdownOpen = false
    @ObservationIgnored private var pointerInside = false

    var active: Bool { titles != nil }

    /// Rebuilding the bars for a screen change drops this with the menus still showing.
    isolated deinit {
        escape.map(NSEvent.removeMonitor)
    }

    /// Clicking the focused workspace: menus on, or off again. Without Accessibility access it explains why not.
    func toggle(_ app: FrontApp, at screenPoint: NSPoint) {
        if active { return end() }
        guard let titles = AppMenus.titles(pid: app.pid), !titles.isEmpty else {
            if !AXIsProcessTrusted() { AppMenus.explainAccess("show \(app.name)'s menus", at: screenPoint) }
            return
        }
        withAnimation(spring) { self.titles = titles }
        // Global key events need Accessibility access, which reading the menus already proved.
        escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.end() }
        }
    }

    /// Opens the menu of the column `id`. Sliding onto another title while it is open switches to that title's menu,
    /// as in the native menu bar.
    func open(_ id: Int, columns: [MenuColumn]) {
        dropdownOpen = true
        var next: Int? = id
        while let current = columns.first(where: { $0.id == next }), let menu = current.menu() {
            openTitle = current.id
            next = AppMenus.popUp(menu, at: current.rect.origin) { point in
                // NSMouseInRect counts the top edge as inside, where the pointer rests when pushed against it.
                columns.first { $0.id != current.id && NSMouseInRect(point, $0.rect, false) }?.id
            }
        }
        openTitle = nil
        dropdownOpen = false
        if !pointerInside { hover(false) }
    }

    func hover(_ inside: Bool) {
        pointerInside = inside
        leave?.cancel()
        guard !inside, active else { return }
        leave = Task {
            try? await Task.sleep(for: .seconds(0.7))
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
