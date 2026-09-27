import AppKit
import LiquidBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    /// Each screen's bar and, as its child, its dropdown.
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
        panels = NSScreen.screens.flatMap { makePanels(for: $0, slot: ExpansionSlot()) }
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
