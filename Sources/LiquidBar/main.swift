import AppKit
import LiquidBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    var panels: [NSPanel] = []
    var islands: [IslandPanel] = []
    var aerospace: AeroSpaceSource?
    var sources: [AnyObject] = []
    var agentSource: AgentSource?
    var scripts: ScriptRunner?
    var configWatcher: ConfigWatcher?
    var sigterm: DispatchSourceSignal?
    #if DEBUG
    var fakes: FakeAgents?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts = ScriptRunner(model: model)
        configWatcher = ConfigWatcher { [weak self] config in self?.apply(config) }
        aerospace = AeroSpaceSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), ClockSource(model: model), NowPlayingSource(model: model), BannerWatcher(model: model), FrontAppSource(model: model)]
        #if DEBUG
        fakes = FakeAgents(model: model) { [weak self] in self?.agentSource?.reload() }
        #endif
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
        let rebuild = config.height != model.config.height || config.agents != model.config.agents
        model.config = config
        scripts?.load(config.left + config.right)
        if config.agents != (agentSource != nil) {
            agentSource = config.agents ? AgentSource(model: model) : nil
            if !config.agents { model.receive([]) }
        }
        if rebuild && !panels.isEmpty { rebuildPanels() }
    }

    func rebuildPanels() {
        (panels + islands).forEach { $0.close() }
        panels = NSScreen.screens.map(makePanel)
        islands = model.config.agents ? NSScreen.screens.map { IslandPanel(screen: $0, model: model, barHeight: model.config.height) } : []
    }

    func makePanel(for screen: NSScreen) -> NSPanel {
        let height = model.config.height
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
            rightWidth: screen.auxiliaryTopRightArea?.width,
            notchHeight: screen.safeAreaInsets.top
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
    /// "banner on|off" stands in for a notification banner, "slow <factor>" slows the fluid down for frame-by-frame captures, and "focus <workspace>" moves the bar's focus alone, and "backdrop <png|off>" puts a picture behind the bar and in its
    /// reflections. "scene running|needsInput|done|error|nowPlaying|clear" shows fake
    /// agents or music in the island.
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
                // Moves the bar's focus without switching AeroSpace, so captures never take the user's workspace away.
                if parts.count == 2, parts[0] == "focus" { return self.model.workspaces.focused = String(parts[1]) }
                if parts.count == 2, parts[0] == "backdrop" { return self.showBackdrop(parts[1] == "off" ? nil : String(parts[1])) }
                if parts.count == 2, parts[0] == "slow", let factor = Double(parts[1]) { return FluidController.slowdown = max(1, factor) }
                if parts.count == 2, parts[0] == "scene" { return self.fakes?.show(String(parts[1])) ?? () }
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
                guard let panel = (self.islands + self.panels).first(where: { $0.frame.contains(point) }) else { return }
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

#if DEBUG
extension AppDelegate {
    private static var backdrop: NSWindow?

    /// A picture behind the bar, as if it were the wallpaper, to judge the fluid on light and dark backdrops.
    func showBackdrop(_ path: String?) {
        Self.backdrop?.close()
        Self.backdrop = nil
        Wallpaper.override = path.map(URL.init(fileURLWithPath:))
        defer { NotificationCenter.default.post(name: Wallpaper.changed, object: nil) }
        guard let path, let full = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.screens.first
        else { return }
        // Only the strip behind the bar, stretched from the picture's top like a wallpaper filling the screen.
        let strip = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 60, width: screen.frame.width, height: 60)
        let rows = Int(Double(full.height) * 60 / screen.frame.height)
        guard let top = full.cropping(to: CGRect(x: 0, y: 0, width: full.width, height: rows)) else { return }
        let image = NSImage(cgImage: top, size: strip.size)
        let window = NSWindow(contentRect: strip, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        let view = NSImageView(image: image)
        view.imageScaling = .scaleAxesIndependently
        window.contentView = view
        window.setFrame(strip, display: true)
        window.orderFrontRegardless()
        Self.backdrop = window
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
case ("agents", 1...2):
    exit(printAgents(arguments.dropFirst().first))
default:
    FileHandle.standardError.write(Data("usage: liquid-bar [trigger <event> | agents [database]]\n".utf8))
    exit(2)
}

// launchd and Finder start us with a minimal PATH; aerospace and script widgets live elsewhere.
setenv("PATH", "/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/\(NSUserName())/bin:\(NSHomeDirectory())/.nix-profile/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
