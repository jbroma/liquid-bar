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
    /// The bars a window covers, whose top edge the pointer is followed to.
    var coveredBars: [NSPanel] = []
    /// The bars slid away in fullscreen, which stay on screen until their animation ends.
    var hiddenBars: Set<ObjectIdentifier> = []
    var edgeMonitor: Any?
    var edgePoll: Task<Void, Never>?
    var pendingRebuild: Task<Void, Never>?
    var missionControlSettle: Task<Void, Never>?
    /// Mission Control's window has been on screen since the bar was raised.
    var missionControlSeen = false
    var pictureTick = 0
    /// Each screen's hover state, closed when the bar's menu opens.
    var slots: [ExpansionSlot] = []
    let settings = SettingsWindow()
    let barMenu = BarMenu()
    let updates = Updates()
    /// Without a relaunch, what read Accessibility at launch or earlier and came up empty reads it again.
    lazy var access = AccessWindow { [model] in
        MenuExtras.refresh(model)
        model.controls.readFocus()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bar, its dropdowns and its menus are dark in either system appearance.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = mainMenu()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { followWindows() }
        }
        // Every Accessibility call waits at most 1s for a busy app instead of the default 6s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        if !AXIsProcessTrusted() {
            log.notice("no Accessibility access: app menus, status items and Focus are unavailable")
            access.show()
        } else if !UserDefaults.standard.bool(forKey: AccessWindow.welcomed) {
            access.show()
        }
        scripts = ScriptRunner(model: model)
        configWatcher = ConfigWatcher { [weak self] config in self?.apply(config) }
        workspaces = WorkspacesSource(model: model)
        clock = ClockSource(model: model)
        sources = [BatterySource(model: model), VolumeSource(model: model), NetworkSource(model: model), NowPlayingSource(model: model), FrontAppSource(model: model), MenuExtrasSource(model: model)]
        rebuildPanels()
        // A secondary click anywhere on a bar opens LiquidBar's own menu; nothing on the bar has another use for it.
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  let window = event.window, window.parent == nil, panels.contains(where: { $0 === window }) else { return event }
            slots.forEach { $0.dismiss() }
            barMenu.show(at: NSEvent.mouseLocation, below: window.frame.minY)
            return nil
        }
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
            MainActor.assumeIsolated { _ = self?.followWindowList() }
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

    /// Reads the strip of desktop picture under each bar again, and keeps the bars above the native menu bar while
    /// they have one: a bar that draws its own copy of what is behind it hides the native menu bar for good, also in
    /// the first frame of Mission Control, which comes before any event.
    func followDesktopPicture() {
        var strips: [String: CGImage] = [:]
        for bar in panels where bar.parent == nil {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(bar.frame) }),
                  let strip = DesktopPicture.strip(of: screen, height: bar.frame.height) else { continue }
            strips[NSStringFromRect(screen.frame)] = strip
        }
        if strips.mapValues(DesktopPicture.digest) != model.desktopStrips.mapValues(DesktopPicture.digest) { model.desktopStrips = strips }
        guard missionControlSettle == nil else { return }
        panels.forEach { $0.level = restingLevel }
    }

    /// Above the native menu bar while the bars draw the desktop picture behind them, and otherwise at the Dock's
    /// level, under it.
    private var restingLevel: NSWindow.Level {
        model.desktopStrips.isEmpty ? barLevel : .init(rawValue: barLevel.rawValue + 5)
    }

    func raiseBarThroughMissionControl(open: Bool) {
        panels.forEach { $0.level = .init(rawValue: barLevel.rawValue + 5) }
        followWindowList()
        missionControlSettle?.cancel()
        // Already up: this event is Mission Control closing.
        let wasUp = missionControlSeen
        // The frosted cover is up from the first event, since the native menu bar shows within a frame or two of it.
        // The same events can come with other things, so it leaves again unless Mission Control's own window shows
        // within 0.4 s, and otherwise stays until that window has left, through the closing animation.
        model.missionControl = true
        missionControlSettle = Task {
            // Mission Control's window can take a moment to show, and is not in every reading of the window list.
            var seen = wasUp, misses = 0
            for tick in 0... {
                guard !Task.isCancelled else { return }
                let shown = missionControlShown()
                seen = seen || shown
                missionControlSeen = seen
                misses = shown ? 0 : misses + 1
                // Gone for three readings in a row once it has been up for a while, or never there.
                if seen ? misses >= 3 && tick > 30 : tick > 8 { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            NativeMenuBar.stopHolding()
            missionControlSeen = false
            model.missionControl = false
            missionControlSettle = nil
            panels.forEach { $0.level = restingLevel }
        }
    }

    private func missionControlShown() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock", let bounds = window[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
            return rect.contains(CGDisplayBounds(CGMainDisplayID()))
        }
    }

    /// Never on screen, since the bar covers the menu bar, but its shortcuts work while a LiquidBar window is in front:
    /// ⌘, ⌘W ⌘M ⌘Q and the Edit commands for the text fields.
    private func mainMenu() -> NSMenu {
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            items.forEach(item.submenu!.addItem)
            return item
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit LiquidBar", action: #selector(quitFromMenu), keyEquivalent: "q")
        [settings, quit].forEach { $0.target = self }
        let main = NSMenu()
        [
            menu("LiquidBar", [settings, .separator(), quit]),
            menu("Edit", [
                NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
                NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
                .separator(),
                NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
                NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
                NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
                NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            ]),
            menu("Window", [
                NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
                NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
            ]),
        ].forEach(main.addItem)
        return main
    }

    @objc private func showSettings() { settings.show() }
    @objc private func quitFromMenu() { quit() }

    /// Opening LiquidBar again while it runs, from Finder or `open -a LiquidBar`, shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
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

    /// Follows the on-screen windows. Hides a screen's bar as macOS hides the menu bar: in a fullscreen Space, and
    /// while a normal window covers the whole screen, like a game or a slideshow. There the bar comes back when the
    /// pointer reaches the top edge, and stays while one of its dropdowns or menus is open. Returns whether a bar shows
    /// while hidden at rest.
    @discardableResult
    func followWindowList() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        func bounds(layer: CGWindowLevelKey, owner: String? = nil) -> [CGRect] {
            windows.compactMap { window in
                guard window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(layer)), let bounds = window[kCGWindowBounds as String],
                      owner == nil || window[kCGWindowOwnerName as String] as? String == owner else { return nil }
                return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
            }
        }
        let covering = bounds(layer: .normalWindow)
        // In a fullscreen Space the native menu bar comes on screen when the pointer reaches the top edge, and leaves
        // once the pointer has left it and the title bar.
        let menuBars = bounds(layer: .mainMenuWindow, owner: "Window Server")
        let menuOpen = NSApp.windows.contains { $0.isVisible && $0.level > barLevel && !($0 is BarPanel) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let fullscreen = Desktops.fullscreenScreens()
        let pointer = NSEvent.mouseLocation
        coveredBars = []
        var revealed = false
        for (bar, slot) in zip(panels.filter { $0.parent == nil }, slots) {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(bar.frame) }) else { continue }
            // CoreGraphics measures from the top of the primary screen, AppKit from its bottom.
            let frame = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            let covered = covering.contains { $0.contains(frame) } || fullscreen.contains(screen)
            // A notched screen keeps the native menu bar's window on screen in fullscreen, in the strip beside the
            // camera, so there the pointer says when the menu bar shows: from the top edge, for as long as it is on the bar.
            let onBar = NSMouseInRect(pointer, bar.frame, false)
            let visible = !hiddenBars.contains(ObjectIdentifier(bar))
            let native = screen.auxiliaryTopLeftArea == nil ? menuBars.contains { $0.intersects(frame) }
                : onBar && (visible || pointer.y >= bar.frame.maxY - 1)
            // Only a bar already showing is kept: a pulse, like the charger plugged in, must not bring a hidden one back.
            let shown = native || visible && (slot.owner != nil || menuOpen)
            let hide = covered && !shown
            if hide == visible { slide(bar, away: hide) }
            if covered { coveredBars.append(bar) }
            revealed = revealed || covered && shown
        }
        let covered = Set(coveredBars.compactMap { bar in NSScreen.screens.first { $0.frame.contains(bar.frame) }.map { NSStringFromRect($0.frame) } })
        if covered != model.coveredScreens { model.coveredScreens = covered }
        // Every fifth second: a dynamic desktop picture changes slowly, and a new one is rare.
        pictureTick += 1
        if pictureTick % 5 == 0 { followDesktopPicture() }
        watchTopEdge(!coveredBars.isEmpty)
        // The privacy dot is a small WindowServer window at the top right, on screen only while the dot shows.
        let dot = windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Window Server", (window[kCGWindowLayer as String] as? Int ?? 0) > 1000,
                  let bounds = window[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
            return rect.minY < 10 && rect.width < 40 && rect.height < 40
        }
        if model.privacyDot != dot { model.privacyDot = dot }
        // Reapplied every tick, as yabai reapplies it on Space changes.
        NativeMenuBar.setAlpha(0)
        return revealed
    }

    /// Slides a bar up out of the screen's top edge while it fades, or back down, as macOS moves the menu bar in
    /// fullscreen. The content moves inside its window, which leaves the screen once the bar is away.
    private func slide(_ bar: NSPanel, away: Bool) {
        guard let content = bar.contentView else { return }
        let id = ObjectIdentifier(bar)
        if away { hiddenBars.insert(id) } else { hiddenBars.remove(id) }
        if !away, !bar.isVisible {
            content.setFrameOrigin(NSPoint(x: 0, y: content.frame.height))
            bar.alphaValue = 0
            bar.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = away ? 0.18 : 0.22
            animation.timingFunction = CAMediaTimingFunction(name: away ? .easeIn : .easeOut)
            content.animator().setFrameOrigin(NSPoint(x: 0, y: away ? content.frame.height : 0))
            bar.animator().alphaValue = away ? 0 : 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.hiddenBars.contains(id) == true { bar.orderOut(nil) }
            }
        }
    }

    /// The 1s poll is too slow for the pointer reaching the top edge. While a window covers a bar, the pointer at that
    /// screen's top edge starts a faster poll, which runs until the pointer has left the edge and the bar has hidden
    /// again.
    private func watchTopEdge(_ watch: Bool) {
        if !watch {
            edgeMonitor.map(NSEvent.removeMonitor)
            edgeMonitor = nil
        } else if edgeMonitor == nil {
            edgeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollFromTopEdge() }
            }
        }
    }

    private func pollFromTopEdge() {
        // From a few points below the edge: the pointer's position can lag the event that brought it there, and no
        // later event comes while it rests at the edge.
        guard edgePoll == nil, pointerAtTopEdge else { return }
        edgePoll = Task {
            while followWindowList() || pointerAtTopEdge { try? await Task.sleep(for: .milliseconds(50)) }
            edgePoll = nil
        }
    }

    private var pointerAtTopEdge: Bool {
        let pointer = NSEvent.mouseLocation
        // NSMouseInRect counts the top edge as inside, where the pointer rests when pushed against it.
        return coveredBars.contains { NSMouseInRect(pointer, $0.frame, false) && pointer.y >= $0.frame.maxY - 6 }
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
        hiddenBars = []
        slots = NSScreen.screens.map { ExpansionSlot(screen: $0.frame) }
        panels = zip(NSScreen.screens, slots).flatMap { makePanels(for: $0, slot: $1) }
        NativeMenuBar.bars = (panels.map { UInt32($0.windowNumber) }, Int32(barLevel.rawValue + 5))
        followDesktopPicture()
    }

    func makePanels(for screen: NSScreen, slot: ExpansionSlot) -> [NSPanel] {
        // Exactly as tall as the native menu bar under it, which macOS keeps banners, Notification Center and
        // windows below. On a notched screen that is one point taller than the notch (33 vs 32).
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let (left, right) = (screen.auxiliaryTopLeftArea?.width, screen.auxiliaryTopRightArea?.width)
        let metrics = BarMetrics(screen: screen.frame, height: height, left: left, right: right)
        let bar = panel(frame, root: BarView(model: model).environment(slot).environment(\.bar, metrics))
        // Set explicitly, the bar takes clicks over its whole strip, clear pixels included: a right-click beside the
        // items opens the bar's menu rather than reaching the desktop under it.
        bar.ignoresMouseEvents = false
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
    /// The dropdowns take typing, like a Wi-Fi password; the bar itself never does.
    override var canBecomeKey: Bool { becomesKeyOnlyIfNeeded }

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
