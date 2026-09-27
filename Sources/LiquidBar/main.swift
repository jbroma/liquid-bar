import AppKit
import LiquidBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    /// Each screen's bar and, as its child, its dropdown.
    var panels: [NSPanel] = []
    var slots: [ExpansionSlot] = []
    var aerospace: AeroSpaceSource?
    var sources: [AnyObject] = []
    var scripts: ScriptRunner?
    var configWatcher: ConfigWatcher?
    var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts = ScriptRunner(model: model)
        configWatcher = ConfigWatcher { [weak self] config in self?.apply(config) }
        aerospace = AeroSpaceSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), ClockSource(model: model), NowPlayingSource(model: model), FrontAppSource(model: model), MenuExtrasSource(model: model)]
        rebuildPanels()
        // launchd stops us with SIGTERM; take the subscriber down too so it is not left orphaned inside AeroSpace.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.aerospace?.subscriber?.terminate() }
            exit(0)
        }
        sigterm?.resume()
        // A new instance (launchd restart, `make run`) replaces any running one instead of stacking a second bar on top.
        let pid = String(getpid())
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: quitNotification, object: nil, queue: .main) { [weak self] note in
            guard note.object as? String != pid else { return }
            MainActor.assumeIsolated { self?.aerospace?.subscriber?.terminate() }
            exit(0)
        }
        center.postNotificationName(quitNotification, object: pid, userInfo: nil, deliverImmediately: true)
        #if DEBUG
        installDebugInput()
        #endif
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
    }

    func apply(_ config: Config) {
        model.config = config
        scripts?.load(config.left + config.right)
    }

    func rebuildPanels() {
        panels.forEach { $0.close() }
        slots = NSScreen.screens.map { _ in ExpansionSlot() }
        panels = zip(NSScreen.screens, slots).flatMap(makePanels)
    }

    func makePanels(for screen: NSScreen, slot: ExpansionSlot) -> [NSPanel] {
        // Exactly as tall as the native menu bar under it, which macOS keeps banners, Notification Center and
        // windows below. On a notched screen that is one point taller than the notch (33 vs 32), invisible on black.
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        // Pure black, like the bezel and the notch on a mini-LED panel.
        let bar = panel(frame, background: .black, root: BarView(
            model: model,
            screenFrame: screen.frame,
            height: height,
            leftWidth: screen.auxiliaryTopLeftArea?.width,
            rightWidth: screen.auxiliaryTopRightArea?.width,
            slot: slot
        ).environment(slot))
        // One dropdown window on each side of the notch, from the bar down to the bottom of the screen. Their clear
        // pixels let the pointer through, as long as `ignoresMouseEvents` is never set.
        let rightX = screen.auxiliaryTopRightArea.map { screen.frame.width - $0.width } ?? screen.frame.width / 2
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? screen.frame.width / 2
        let dropdowns = [(0, leftWidth, true), (rightX, screen.frame.width - rightX, false)].map { originX, width, left in
            let height = screen.frame.height - frame.height
            let dropdown = panel(
                NSRect(x: screen.frame.minX + originX, y: frame.minY - height, width: width, height: height),
                background: .clear,
                root: DropdownView(model: model, originX: originX, left: left).environment(slot)
            )
            dropdown.becomesKeyOnlyIfNeeded = true
            bar.addChildWindow(dropdown, ordered: .above)
            return dropdown
        }
        return [bar] + dropdowns
    }

    private func panel(_ frame: NSRect, background: NSColor, root: some View) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = barLevel
        panel.backgroundColor = background
        panel.isOpaque = background == .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        return panel
    }
}

#if DEBUG
extension AppDelegate {
    /// Test hook: macOS refuses synthetic CGEvents from unprivileged tools, so verification scripts
    /// inject "click x y" / "scroll x y lines" (screen points, top-left origin) through the panel's own event path.
    /// A click lands where the real pointer is, so warp there first. "drag x y x2" drags horizontally from x to x2,
    /// and "down x y" / "up x y" send half a click, to hold a control pressed.
    /// "tick" advances the clock a minute, and
    /// "hover <item> on|off" stands in for the pointer entering or leaving an item.
    func installDebugInput() {
        // Popup menus wait for a real click, and distributed notifications do not arrive while one tracks the mouse,
        // so debug builds close them after 4s by themselves.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let menu = note.object as? NSMenu
            guard menu?.supermenu == nil else { return }
            let timer = Timer(timeInterval: 4, repeats: false) { _ in menu?.cancelTracking() }
            RunLoop.main.add(timer, forMode: .common)
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("dev.liquidbar.debug"), object: nil, queue: .main) { [weak self] note in
            let command = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let parts = command?.split(separator: " ") else { return }
                if parts == ["tick"] { return self.model.now += 60 }
                if parts.count == 3, parts[0] == "hover" { return self.slots.first?.hover(String(parts[1]), parts[2] == "on") ?? () }
                guard parts.count >= 3,
                      let x = Double(parts[1]), let y = Double(parts[2]) else { return }
                let top = NSScreen.screens[0].frame.maxY
                let point = NSPoint(x: x, y: top - y)
                guard let panel = self.panels.first(where: { $0.frame.contains(point) }) else { return }
                let local = panel.convertPoint(fromScreen: point)
                if parts[0] == "scroll", parts.count == 4, let lines = Int32(parts[3]) {
                    // Synthetic scroll NSEvents carry no window, so AppKit drops them; hand it to the view under the point.
                    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
                    @MainActor func catcher(in view: NSView) -> ScrollCatcher.CatcherView? {
                        if let hit = view as? ScrollCatcher.CatcherView, hit.convert(hit.bounds, to: nil).contains(local) { return hit }
                        return view.subviews.lazy.compactMap(catcher).first
                    }
                    if let event = NSEvent(cgEvent: cg), let view = panel.contentView.flatMap(catcher) { view.scrollWheel(with: event) }
                    return
                }
                var steps: [(NSEvent.EventType, CGFloat)] = [(.leftMouseDown, local.x), (.leftMouseUp, local.x)]
                if parts[0] == "down" { steps = [(.leftMouseDown, local.x)] }
                if parts[0] == "up" { steps = [(.leftMouseUp, local.x)] }
                if parts[0] == "drag", parts.count == 4, let x2 = Double(parts[3]) {
                    let end: CGFloat = local.x + CGFloat(x2 - x)
                    let drags: [(NSEvent.EventType, CGFloat)] = (1...8).map { (.leftMouseDragged, local.x + (end - local.x) * CGFloat($0) / 8) }
                    steps = [(.leftMouseDown, local.x)] + drags + [(.leftMouseUp, end)]
                }
                for (type, x) in steps {
                    let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: local.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    NSApp.sendEvent(event)
                }
            }
        }
    }
}
#endif

/// Above the native menu bar (24), which stays under the bar as a fallback.
let barLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)

let quitNotification = Notification.Name("dev.liquidbar.quit")

let arguments = CommandLine.arguments.dropFirst()
switch (arguments.first, arguments.count) {
case (nil, _):
    break
case ("trigger", 2):
    DistributedNotificationCenter.default().postNotificationName(triggerNotification, object: arguments.last, userInfo: nil, deliverImmediately: true)
    exit(0)
default:
    FileHandle.standardError.write(Data("usage: liquid-bar [trigger <event>]\n".utf8))
    exit(2)
}

// launchd and Finder start us with a minimal PATH; aerospace and script widgets live elsewhere.
setenv("PATH", "/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/\(NSUserName())/bin:\(NSHomeDirectory())/.nix-profile/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
