import AppKit
import ApplicationServices
import IOBluetooth
import LiquidBarCore

// One boundary per subsystem. Each reads nil and does nothing when this macOS lacks what it needs, so a missing
// private symbol costs a feature, never a crash.

/// Runs blocking work, like Accessibility waits, polling loops or Bluetooth's permission prompt, on a GCD thread, so it
/// never holds one of the few threads Swift concurrency shares.
nonisolated func blocking<T>(_ work: @escaping @Sendable () -> sending T) async -> sending T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: work()) }
    }
}

/// A C function from a system framework, or nil when this macOS does not have it.
private nonisolated func systemFunction<T>(_ path: String, _ name: String, as type: T.Type) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, name) else { return nil }
    return unsafeBitCast(pointer, to: type)
}

/// Paired Bluetooth devices through IOBluetooth.
enum Bluetooth {
    /// Whether the controller is on, and the paired devices while it is. The first read asks for Bluetooth access and
    /// waits for the answer, so reads run off the main thread.
    static func read() async -> (on: Bool?, devices: [BluetoothDevice]) {
        await blocking {
            let on = IOBluetoothHostController.default().map { $0.powerState == kBluetoothHCIPowerStateON }
            return (on, on == true ? devices() : [])
        }
    }

    private nonisolated static func devices() -> [BluetoothDevice] {
        deviceRows(((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).map { device in
            let name = device.name ?? device.addressString ?? "Device"
            return BluetoothDevice(id: device.addressString ?? name, name: name, connected: device.isConnected(), battery: battery(device),
                                   symbol: bluetoothSymbol(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor))
        })
    }

    /// The battery fields are private, so each is read only where the device has it.
    private nonisolated static func battery(_ device: IOBluetoothDevice) -> Int? {
        func field(_ key: String) -> Int {
            device.responds(to: NSSelectorFromString(key)) ? (device.value(forKey: key) as? Int) ?? 0 : 0
        }
        return bluetoothBattery(single: field("batteryPercentSingle"), left: field("batteryPercentLeft"), right: field("batteryPercentRight"),
                                combined: field("batteryPercentCombined"))
    }

    /// Connects or disconnects the device. Both wait for the device to answer, so they run off the main thread.
    static func toggle(_ address: String) async {
        await blocking {
            guard let device = IOBluetoothDevice(addressString: address) else { return }
            if device.isConnected() { device.closeConnection() } else { device.openConnection() }
        }
    }
}

/// Dark Mode, read through SkyLight, where System Settings switches it.
enum Appearance {
    private static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let get = systemFunction(framework, "SLSGetAppearanceThemeLegacy", as: (@convention(c) () -> Bool).self)

    static func isDark() -> Bool? {
        get?()
    }
}

/// The native menu bar's opacity, through SkyLight, as yabai's `menubar_opacity` sets it. At 0 it never shows through
/// the glass when the pointer reaches the top edge, and ignores the mouse. It lasts only while this process runs, so
/// the native bar comes back if the bar quits or crashes.
enum NativeMenuBar {
    private nonisolated static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private nonisolated static let connection = systemFunction(framework, "SLSMainConnectionID", as: (@convention(c) () -> Int32).self)
    private nonisolated static let set = systemFunction(framework, "SLSSetMenuBarInsetAndAlpha", as: (@convention(c) (Int32, Double, Double, Float) -> Int32).self)

    private nonisolated static let setShown = systemFunction(framework, "SLSSetMenuBarVisibilityOverrideOnDisplay",
                                                             as: (@convention(c) (Int32, CGDirectDisplayID, Bool) -> Void).self)

    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private nonisolated static let register = systemFunction(framework, "SLSRegisterNotifyProc", as: (@convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32).self)
    private nonisolated(unsafe) static var missionControlHandler: ((UnsafeMutableRawPointer, Bool) -> Void)?

    /// Calls `handler` when Mission Control opens (WindowServer event 1327) or closes (1328). macOS 27 posts 1327 and
    /// 1328 for screen captures instead, and 1325 and 1326 as Mission Control both opens and closes, so there every
    /// event reads as a close, which raises the bar through the animation and lets it settle after.
    static func onMissionControl(context: UnsafeMutableRawPointer, _ handler: @escaping (UnsafeMutableRawPointer, Bool) -> Void) {
        guard let register else { return }
        missionControlHandler = handler
        // On macOS 27 event 1508 comes first: with 1325 as Mission Control opens, and half a second before 1326 as it
        // closes, when the closing animation starts.
        let events: [UInt32] = ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 27, minorVersion: 0, patchVersion: 0)) ? [1508, 1325, 1326] : [1327, 1328]
        for event in events {
            _ = register({ event, _, _, context in
                // Right here, on SkyLight's thread: a hop to the main thread costs the frames the menu bar flashes in.
                NativeMenuBar.raiseBars()
                NativeMenuBar.holdHidden()
                DispatchQueue.main.async { NativeMenuBar.missionControlHandler?(context!, event == 1327) }
            }, event, context)
        }
    }

    nonisolated static func setAlpha(_ alpha: Float) {
        guard let connection, let set else { return }
        _ = set(connection(), 0, 1, alpha)
    }

    private nonisolated static let setLevel = systemFunction(framework, "SLSSetWindowLevel", as: (@convention(c) (Int32, UInt32, Int32) -> Int32).self)
    /// The bars' window numbers and the level they take through Mission Control, set on the main thread whenever the
    /// bars are built and read from SkyLight's.
    nonisolated(unsafe) static var bars: (windows: [UInt32], level: Int32) = ([], 0)

    /// Lifts the bars above the native menu bar straight through the window server, without waiting for AppKit's turn
    /// on the main thread: until they are up, Mission Control's first frames show the native menu bar in their place.
    nonisolated static func raiseBars() {
        guard let connection, let setLevel else { return }
        let bars = bars
        for window in bars.windows { _ = setLevel(connection(), window, bars.level) }
    }

    private nonisolated static let holdQueue = DispatchQueue(label: "dev.liquidbar.menubar", qos: .userInteractive)
    private nonisolated(unsafe) static var holdTimer: DispatchSourceTimer?

    /// Mission Control animates the native menu bar back to full opacity as it opens and closes. A bar without a
    /// background does not cover it, so its opacity is put back to 0 every millisecond until `stopHolding`. That
    /// keeps it away as Mission Control opens. As it closes, macOS still shows it for two or three frames, however
    /// often it is reset, which is what the bar's frosted cover is for.
    nonisolated static func holdHidden() {
        setAlpha(0)
        holdQueue.async {
            guard holdTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: holdQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .nanoseconds(0))
            timer.setEventHandler { setAlpha(0) }
            holdTimer = timer
            timer.resume()
        }
    }

    nonisolated static func stopHolding() {
        holdQueue.async {
            holdTimer?.cancel()
            holdTimer = nil
        }
    }

    /// Keeps the menu bar shown while menu bar auto-hide would hide it, or lets it hide again.
    nonisolated static func setShown(_ shown: Bool) {
        guard let connection, let setShown else { return }
        setShown(connection(), CGMainDisplayID(), shown)
    }
}

/// The desktop picture as it is on screen. macOS tells an app which file is set, but not what a dynamic or aerial
/// picture shows, so the picture is read from its own window, which the window server hands out without Screen
/// Recording access, unlike other apps' windows.
enum DesktopPicture {
    private static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let connection = systemFunction(framework, "SLSMainConnectionID", as: (@convention(c) () -> Int32).self)
    private static let capture = systemFunction(framework, "SLSHWCaptureWindowList",
                                                as: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, UInt32) -> Unmanaged<CFArray>?).self)

    /// The top `height` points of `screen`'s desktop picture.
    static func strip(of screen: NSScreen, height: CGFloat) -> CGImage? {
        guard let connection, let capture, let primary = NSScreen.screens.first else { return nil }
        let frame = CGRect(x: screen.frame.minX, y: primary.frame.height - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // The picture's window covers the screen, under the desktop's icons. Under it is the window server's black one.
        let picture = windows.compactMap { window -> (id: UInt32, layer: Int)? in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer < Int(CGWindowLevelForKey(.desktopIconWindow)),
                  window[kCGWindowOwnerName as String] as? String != "Window Server",
                  let bounds = window[kCGWindowBounds as String], CGRect(dictionaryRepresentation: bounds as! CFDictionary) == frame,
                  let id = window[kCGWindowNumber as String] as? Int else { return nil }
            return (UInt32(id), layer)
        }.max { $0.layer < $1.layer }
        guard var id = picture?.id,
              // Ignoring the clip shape, at the best resolution.
              let image = (capture(connection(), &id, 1, (1 << 11) | (1 << 8))?.takeRetainedValue() as? [CGImage])?.first
        else { return nil }
        return image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: Int(height * CGFloat(image.height) / screen.frame.height)))
    }

    /// Enough of a strip to tell whether it has changed.
    static func digest(_ strip: CGImage) -> Int {
        guard let data = strip.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        var hasher = Hasher()
        for offset in stride(from: 0, to: CFDataGetLength(data), by: 4099) { hasher.combine(bytes[offset]) }
        return hasher.finalize()
    }
}

/// The macOS desktops through SkyLight, read as yabai reads them. macOS has no API to switch desktops, so switching
/// presses the "Switch to Desktop N" shortcut.
enum Desktops {
    private static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let connection = systemFunction(framework, "SLSMainConnectionID", as: (@convention(c) () -> Int32).self)
    private static let copySpaces = systemFunction(framework, "SLSCopyManagedDisplaySpaces", as: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self)
    private static let activeSpace = systemFunction(framework, "SLSGetActiveSpace", as: (@convention(c) (Int32) -> UInt64).self)
    private static let copyWindows = systemFunction(
        framework, "SLSCopyWindowsWithOptionsAndTags",
        as: (@convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?).self
    )

    /// The desktops of the display the user is on, the one holding the active Space.
    static func current() -> DisplaySpaces? {
        guard let connection, let copySpaces, let activeSpace,
              let list = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let displays = parseDisplaySpaces(list)
        let active = activeSpace(connection())
        return displays.first { $0.current == active } ?? displays.first
    }

    /// The screens whose current Space is a fullscreen one. SkyLight names a display by its UUID, or "Main" while
    /// displays share their Spaces.
    static func fullscreenScreens() -> [NSScreen] {
        guard let connection, let copySpaces, let list = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        let fullscreen = list.filter { ($0["Current Space"] as? [String: Any])?["type"] as? Int == 4 }.compactMap { $0["Display Identifier"] as? String }
        return NSScreen.screens.filter { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
            return fullscreen.contains(CFUUIDCreateString(nil, uuid) as String) || fullscreen.contains("Main") && screen == NSScreen.screens.first
        }
    }

    /// The current display's desktops with the regular apps' windows on each.
    static func read() -> WorkspaceState? {
        guard let desktops = current(), let connection, let copyWindows else { return nil }
        var windows: [UInt64: [Int]] = [:]
        for space in desktops.desktops.prefix(9) {
            // Options 2 with tag bit 1, as in yabai's `space_window_list_for`: the Space's windows front to back,
            // without minimized ones.
            var set: UInt64 = 1, clear: UInt64 = 0
            windows[space] = copyWindows(connection(), 0, [space] as CFArray, 2, &set, &clear)?.takeRetainedValue() as? [Int] ?? []
        }
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var owners: [Int: String] = [:]
        for window in info where window[kCGWindowLayer as String] as? Int == 0 {
            guard let id = window[kCGWindowNumber as String] as? Int, let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier
            else { continue }
            owners[id] = bundleID
        }
        return WorkspaceState(desktops: desktops, windows: windows, owners: owners)
    }

    /// The shortcut that switches to desktop `n`, or nil while it is off.
    static func shortcut(_ n: Int) -> KeyShortcut? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        return desktopShortcut(n, in: hotkeys)
    }

    static func press(_ shortcut: KeyShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: down)
            event?.flags = CGEventFlags(rawValue: shortcut.modifiers)
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Apple's own status items, which the bar covers, through Accessibility: Control Center's, the clock's and Focus's.
enum SystemControlCenter {
    nonisolated static let controlCenter = "com.apple.menuextra.controlcenter"
    /// Opens Notification Center.
    nonisolated static let clock = "com.apple.menuextra.clock"
    /// Shown while a Focus is on, unless the user set it to always show in the menu bar.
    nonisolated static let focus = "com.apple.menuextra.focusmode"

    private nonisolated static func running(_ bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    /// Control Center owns the panels.
    private nonisolated static var pid: pid_t? { running("com.apple.controlcenter") }

    /// The owner of Apple's status items: MenuBarAgent since macOS 27, Control Center before.
    private nonisolated static var owner: pid_t? { running("com.apple.MenuBarAgent") ?? pid }

    /// Apple's status items by identifier, empty without Accessibility access.
    nonisolated static func extras() -> [String: AXUIElement] {
        guard AXIsProcessTrusted(), let owner else { return [:] }
        return Dictionary(MenuExtras.items(pid: owner).compactMap { item in AX.string(item, "AXIdentifier").map { ($0, item) } }) { first, _ in first }
    }

    private nonisolated(unsafe) static var observer: AXObserver?
    private static var itemsChanged: (() -> Void)?

    /// Calls `handler` whenever one of Apple's status items comes or goes, once Accessibility access allows it.
    static func onItemsChanged(_ handler: @escaping () -> Void) {
        guard observer == nil, AXIsProcessTrusted(), let owner,
              AXObserverCreate(owner, { _, _, _, _ in MainActor.assumeIsolated { SystemControlCenter.itemsChanged?() } }, &observer) == .success,
              let observer
        else { return }
        itemsChanged = handler
        let app = AXUIElementCreateApplication(owner)
        for name in [kAXCreatedNotification, kAXUIElementDestroyedNotification] { AXObserverAddNotification(observer, app, name as CFString, nil) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Whether a Focus is on, read from its status item. Nil without Accessibility access. The Focus database itself
    /// needs Full Disk Access, and the DoNotDisturb framework refuses clients without Apple's entitlement.
    static func focusIsOn() -> Bool? {
        let items = extras()
        return items.isEmpty ? nil : items[focus] != nil
    }

    /// Opens the real Control Center on one of its modules, as a click on the module would, and leaves it open for
    /// the user: Sound lists every output, AirPlay receivers included. It blocks until the module has opened, and
    /// returns false when it did not, or without Accessibility.
    nonisolated static func showModule(_ id: String) -> Bool {
        guard let (app, _) = openPanel() else { return false }
        guard let module = waitFor(app, { $0.filter { AX.string($0, "AXIdentifier") == id } }).first else { return false }
        return AX.press(module)
    }

    /// Presses Apple's status item `id`, as a click on it in the native menu bar does: Control Center's opens or
    /// closes its panel, the clock's Notification Center. It blocks until pressed, and returns false when the item is
    /// missing, or without Accessibility.
    @discardableResult
    nonisolated static func press(_ id: String) -> Bool {
        guard let item = extras()[id] else { return false }
        return shown(item) { AX.press(item) }
    }

    /// Opens Control Center's main view, and returns Control Center and its status item. Nil without Accessibility access.
    private nonisolated static func openPanel() -> (app: AXUIElement, item: AXUIElement)? {
        guard let item = extras()[controlCenter], let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        close(app, item)
        // The status item keeps its own idea of whether the panel is open, which drifts when the panel closes by
        // itself; then the first press only resets it.
        shown(item) {
            for _ in 0..<2 where windows(app).isEmpty {
                AX.press(item)
                for _ in 0..<40 where windows(app).isEmpty { usleep(10_000) }
            }
        }
        return (app, item)
    }

    /// Runs `work` with the native menu bar shown. With menu bar auto-hide on, a status item sits above the screen,
    /// where a press opens nothing. What the press opened stays open once the menu bar hides again.
    private nonisolated static func shown<T>(_ item: AXUIElement, _ work: () -> T) -> T {
        NativeMenuBar.setShown(true)
        defer { NativeMenuBar.setShown(false) }
        for _ in 0..<50 where position(item).y < 0 { usleep(10_000) }
        return work()
    }

    private nonisolated static func position(_ item: AXUIElement) -> CGPoint {
        var point = CGPoint.zero
        if let value = AX.attribute(item, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
        return point
    }

    private nonisolated static func windows(_ app: AXUIElement) -> [AXUIElement] {
        AX.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    /// The panel's controls, which sit in its window's hosting view.
    private nonisolated static func controls(_ app: AXUIElement) -> [AXUIElement] {
        windows(app).flatMap { AX.children($0).flatMap(AX.children) }
    }

    /// What `find` picks from the panel's controls, once it picks any, within 1.5s.
    private nonisolated static func waitFor(_ app: AXUIElement, _ find: ([AXUIElement]) -> [AXUIElement]) -> [AXUIElement] {
        for _ in 0..<150 {
            let found = find(controls(app))
            if !found.isEmpty { return found }
            usleep(10_000)
        }
        return []
    }

    /// Control Center's Focus module, "controlcenter-focus-modes" before macOS 27 and "controlcenter-focus-modes-compact-2" since.
    private nonisolated static func isFocusModule(_ element: AXUIElement) -> Bool {
        AX.string(element, "AXIdentifier")?.hasPrefix("controlcenter-focus-modes") == true
    }

    /// Presses the status item until the panel is gone. From a module's detail view a press goes back to the main
    /// view, and the panel takes a moment to close, so each press waits for one or the other before the next.
    private nonisolated static func close(_ app: AXUIElement, _ item: AXUIElement) {
        func mainView() -> Bool { controls(app).contains(where: isFocusModule) }
        for _ in 0..<3 where !windows(app).isEmpty {
            let fromDetail = !mainView()
            AX.press(item)
            for _ in 0..<100 where !windows(app).isEmpty && !(fromDetail && mainView()) { usleep(10_000) }
        }
    }
}

/// Opens a module of the real Control Center off the main thread, or the settings pane when it cannot.
func showControlCenterModule(_ id: String, else pane: String) {
    Task {
        if await !blocking({ SystemControlCenter.showModule(id) }) { openSettings(pane) }
    }
}

func openSettings(_ pane: String) {
    shell("open 'x-apple.systempreferences:\(pane)'")
}
