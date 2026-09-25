import AppKit
import LiquidBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    var panels: [NSPanel] = []
    var aerospace: AeroSpaceSource?
    var sources: [AnyObject] = []
    var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        aerospace = AeroSpaceSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), ClockSource(model: model)]
        // launchd stops us with SIGTERM; take the subscriber down too so it is not left orphaned inside AeroSpace.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.aerospace?.subscriber?.terminate() }
            exit(0)
        }
        sigterm?.resume()
        #if DEBUG
        installDebugInput()
        #endif
        rebuildPanels()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
    }

    func rebuildPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map(makePanel)
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
    func installDebugInput() {
        DistributedNotificationCenter.default().addObserver(forName: .init("dev.liquidbar.debug"), object: nil, queue: .main) { [weak self] note in
            let command = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let parts = command?.split(separator: " "), parts.count >= 3,
                      let x = Double(parts[1]), let y = Double(parts[2]) else { return }
                let top = NSScreen.screens[0].frame.maxY
                let point = NSPoint(x: x, y: top - y)
                guard let panel = self.panels.first(where: { $0.frame.contains(point) }) else { return }
                let local = panel.convertPoint(fromScreen: point)
                if parts[0] == "scroll", parts.count == 4, let lines = Int32(parts[3]) {
                    // Synthetic scroll NSEvents carry no window, so AppKit drops them; hand it to the view under the point.
                    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
                    func catcher(in view: NSView) -> ScrollCatcher.CatcherView? {
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

// launchd and Finder start us with a minimal PATH; aerospace and script widgets live elsewhere.
setenv("PATH", "/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/\(NSUserName())/bin:\(NSHomeDirectory())/.nix-profile/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
