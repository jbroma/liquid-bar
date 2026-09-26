import AppKit
import LiquidBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    var panels: [NSPanel] = []
    var aerospace: AeroSpaceSource?
    var sources: [AnyObject] = []
    var scripts: ScriptRunner?
    var configWatcher: ConfigWatcher?
    var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts = ScriptRunner(model: model)
        configWatcher = ConfigWatcher { [weak self] config in self?.apply(config) }
        aerospace = AeroSpaceSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), ClockSource(model: model), NowPlayingSource(model: model), BannerWatcher(model: model), FrontAppSource(model: model)]
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
        let rebuild = config.height != model.config.height
        model.config = config
        scripts?.load(config.left + config.right)
        if rebuild && !panels.isEmpty { rebuildPanels() }
    }

    func rebuildPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map(makePanel)
    }

    func makePanel(for screen: NSScreen) -> NSPanel {
        let height = model.config.height + (screen.auxiliaryTopLeftArea == nil ? 0 : Band.chin)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the auto-hidden native menu bar, which slides in at .mainMenu level on hover.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: BarView(
            model: model,
            screenFrame: screen.frame,
            leftWidth: screen.auxiliaryTopLeftArea?.width,
            rightWidth: screen.auxiliaryTopRightArea?.width
        ))
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
    /// A click lands where the real pointer is, so warp there first. "tick" advances the clock a minute, and
    /// "banner on|off" stands in for a notification banner.
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
                if parts == ["banner", "on"] || parts == ["banner", "off"] {
                    // Stands in for a banner when this process has no Accessibility access to see real ones.
                    let screen = NSScreen.screens[0].frame
                    self.model.banner = parts[1] == "on" ? CGRect(x: screen.maxX - 360, y: 16, width: 344, height: 56) : nil
                    return
                }
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
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    NSApp.sendEvent(event)
                }
            }
        }
    }
}
#endif

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
