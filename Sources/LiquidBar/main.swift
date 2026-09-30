import AppKit
import LiquidBarCore
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BarModel()
    /// Each screen's bar and, as its children, its two dropdown windows.
    var panels: [NSPanel] = []
    var workspaces: WorkspacesSource?
    var sources: [AnyObject] = []
    var clock: ClockSource?
    var scripts: ScriptRunner?
    var configWatcher: ConfigWatcher?
    var sigterm: DispatchSourceSignal?
    var fullscreenPoll: Timer?
    var pendingRebuild: Task<Void, Never>?
    var missionControlSettle: Task<Void, Never>?
    /// Without a relaunch, what read Accessibility at launch or earlier and came up empty reads it again.
    let about = AboutWindow()
    lazy var access = AccessWindow { [model] in
        MenuExtras.refresh(model)
        model.controls.readFocus()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bar, its dropdowns and its menus are dark in either system appearance.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Every Accessibility call waits at most 1s for a busy app instead of the default 6s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        if !AXIsProcessTrusted() {
            log.notice("no Accessibility access: app menus, status items and Focus are unavailable")
            access.show()
        }
        scripts = ScriptRunner(model: model)
        configWatcher = ConfigWatcher { [weak self] config in self?.apply(config) }
        workspaces = WorkspacesSource(model: model)
        clock = ClockSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), NowPlayingSource(model: model), FrontAppSource(model: model), MenuExtrasSource(model: model)]
        rebuildPanels()
        // launchd stops us with SIGTERM.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.quit() }
        }
        sigterm?.resume()
        // A new instance (launchd restart, `make run`) replaces any running one instead of stacking a second bar on top.
        let pid = String(getpid())
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: quitNotification, object: nil, queue: .main) { [weak self] note in
            guard note.object as? String != pid else { return }
            MainActor.assumeIsolated { self?.quit() }
        }
        center.postNotificationName(quitNotification, object: pid, userInfo: nil, deliverImmediately: true)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        // Switching menu bar auto-hide changes the strip macOS reserves, and so the bar's height.
        center.addObserver(forName: .init("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        // Polled: no notification fires when a covering window closes, a fullscreen animation settles, or the privacy
        // dot comes and goes.
        watchMissionControl()
        fullscreenPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followWindowList() }
        }
    }

    /// Mission Control puts the native menu bar back at full opacity as it opens and closes, and it fades out over
    /// several frames, so the poll cannot hide it in time. Until the animation settles, the bar sits above the menu bar.
    func watchMissionControl() {
        NativeMenuBar.onMissionControl(context: Unmanaged.passUnretained(self).toOpaque()) { context, opened in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.raiseBarThroughMissionControl(open: opened) }
        }
    }

    func raiseBarThroughMissionControl(open: Bool) {
        panels.forEach { $0.level = .init(rawValue: barLevel.rawValue + 5) }
        followWindowList()
        missionControlSettle?.cancel()
        guard !open else { return }
        missionControlSettle = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            panels.forEach { $0.level = barLevel }
        }
    }

    /// Takes the AeroSpace subscriber down too so it is not left orphaned inside AeroSpace.
    func quit() {
        workspaces?.feed?.stop()
        exit(0)
    }

    /// Mirroring and resolution changes post several notifications while the geometry settles; build once at the end.
    func scheduleRebuild() {
        pendingRebuild?.cancel()
        pendingRebuild = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rebuildPanels()
        }
    }

    /// Follows the on-screen windows. Hides a screen's bar while a normal window covers that whole screen: native
    /// fullscreen on a screen without a notch, a game, a slideshow. A notched screen keeps fullscreen windows below the
    /// camera, so its bar stays.
    func followWindowList() {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let covering = windows.compactMap { window -> CGRect? in
            guard window[kCGWindowLayer as String] as? Int == 0, let bounds = window[kCGWindowBounds as String] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for bar in panels where bar.parent == nil {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(bar.frame) }) else { continue }
            // CoreGraphics measures from the top of the primary screen, AppKit from its bottom.
            let frame = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            let covered = covering.contains { $0.contains(frame) }
            if covered == bar.isVisible { covered ? bar.orderOut(nil) : bar.orderFrontRegardless() }
        }
        // The privacy dot is a small WindowServer window at the top right, on screen only while the dot shows.
        let dot = windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Window Server", (window[kCGWindowLayer as String] as? Int ?? 0) > 1000,
                  let bounds = window[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
            return rect.minY < 10 && rect.width < 40 && rect.height < 40
        }
        if model.privacyDot != dot { model.privacyDot = dot }
        // While a fullscreen window hides a bar, the native menu bar is the way to that app's menus. Reapplied every
        // tick, as yabai reapplies it on Space changes.
        NativeMenuBar.setAlpha(panels.contains { $0.parent == nil && !$0.isVisible } ? 1 : 0)
    }

    func apply(_ config: Config) {
        model.config = config
        workspaces?.update()
        scripts?.load(config.left + config.right)
        clock?.tick()
    }

    func rebuildPanels() {
        trace("rebuild panels")
        panels.forEach { $0.close() }
        panels = NSScreen.screens.flatMap { makePanels(for: $0, slot: ExpansionSlot(screen: $0.frame)) }
    }

    func makePanels(for screen: NSScreen, slot: ExpansionSlot) -> [NSPanel] {
        // Exactly as tall as the native menu bar under it, which macOS keeps banners, Notification Center and
        // windows below. On a notched screen that is one point taller than the notch (33 vs 32).
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let (left, right) = (screen.auxiliaryTopLeftArea?.width, screen.auxiliaryTopRightArea?.width)
        let metrics = BarMetrics(screen: screen.frame, height: height, left: left, right: right)
        let bar = panel(frame, root: BarView(model: model).environment(slot).environment(\.bar, metrics))
        // One dropdown window on each side of the notch, from the bar down to the bottom of the screen. Their clear
        // pixels let the pointer through, as long as `ignoresMouseEvents` is never set.
        let (leftWidth, rightWidth) = (left ?? screen.frame.width / 2, right ?? screen.frame.width / 2)
        let dropdowns = [(0, leftWidth, true), (screen.frame.width - rightWidth, rightWidth, false)].map { originX, width, left in
            let height = screen.frame.height - frame.height
            let dropdown = panel(
                NSRect(x: screen.frame.minX + originX, y: frame.minY - height, width: width, height: height),
                root: DropdownView(model: model, originX: originX, left: left).environment(slot)
            )
            dropdown.becomesKeyOnlyIfNeeded = true
            bar.addChildWindow(dropdown, ordered: .above)
            return dropdown
        }
        return [bar] + dropdowns
    }

    private func panel(_ frame: NSRect, root: some View) -> NSPanel {
        let panel = BarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = barLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        return panel
    }
}

/// AppKit pushes a window below the menu bar when its level is under the menu bar's; the bar sits over that strip.
final class BarPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The Dock's level (20), below Notification Center (21) so banners draw over the bar as over the native menu bar. The
/// native menu bar (24) is invisible and ignores the mouse, so the bar need not sit above it.
let barLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))

/// Read with `log show --predicate 'subsystem == "dev.liquidbar"'`; launchd discards stderr.
let log = Logger(subsystem: "dev.liquidbar", category: "bar")

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
