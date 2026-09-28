import AppKit
import ApplicationServices
import IOBluetooth
import LiquidBarCore

// One boundary per subsystem behind the Control Center dropdown. Each reads nil and does nothing when this macOS
// lacks what it needs, so a missing private symbol costs a tile, never a crash.

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

/// An instance of a class from a private framework, or nil when this macOS does not have it.
private func privateObject(_ framework: String, _ className: String) -> NSObject? {
    dlopen("/System/Library/PrivateFrameworks/\(framework).framework/\(framework)", RTLD_LAZY)
    return (NSClassFromString(className) as? NSObject.Type)?.init()
}

/// `object`'s implementation of the method `name`, cast to its C signature, or nil when the object lacks it.
private func method<T>(_ object: NSObject?, _ name: String, as type: T.Type) -> T? {
    guard let object, object.responds(to: NSSelectorFromString(name)) else { return nil }
    return unsafeBitCast(object.method(for: NSSelectorFromString(name)), to: type)
}

/// The built-in display's brightness, through DisplayServices, the private framework behind the brightness keys.
enum DisplayBrightness {
    private static let framework = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let get = systemFunction(framework, "DisplayServicesGetBrightness", as: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    private static let set = systemFunction(framework, "DisplayServicesSetBrightness", as: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)

    private static var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func read() -> Double? {
        guard let get, let display else { return nil }
        var value: Float = 0
        return get(display, &value) == 0 ? Double(value) : nil
    }

    static func write(_ value: Double) {
        guard let set, let display else { return }
        _ = set(display, Float(value))
    }
}

/// The built-in keyboard's backlight, through CoreBrightness's KeyboardBrightnessClient, which the keys use.
enum KeyboardBrightness {
    private static let client = privateObject("CoreBrightness", "KeyboardBrightnessClient")
    private static let get = method(client, "brightnessForKeyboard:", as: (@convention(c) (NSObject, Selector, UInt64) -> Float).self)
    private static let set = method(client, "setBrightness:forKeyboard:", as: (@convention(c) (NSObject, Selector, Float, UInt64) -> Bool).self)

    private static var keyboard: UInt64? {
        let ids = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let client, client.responds(to: ids) else { return nil }
        return (client.perform(ids)?.takeRetainedValue() as? [NSNumber])?.first?.uint64Value
    }

    static func read() -> Double? {
        guard let client, let get, let keyboard else { return nil }
        return Double(get(client, NSSelectorFromString("brightnessForKeyboard:"), keyboard))
    }

    static func write(_ value: Double) {
        guard let client, let set, let keyboard else { return }
        _ = set(client, NSSelectorFromString("setBrightness:forKeyboard:"), Float(value), keyboard)
    }
}

/// Bluetooth power and paired devices through IOBluetooth.
enum Bluetooth {
    /// No public API switches the controller; this is what System Settings calls.
    private static let setPower = systemFunction("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", "IOBluetoothPreferenceSetControllerPowerState",
                                                 as: (@convention(c) (Int32) -> Void).self)

    static var canSwitch: Bool { setPower != nil }

    static func setOn(_ on: Bool) {
        setPower?(on ? 1 : 0)
    }

    /// Whether the controller is on, and the paired devices while it is. The first read asks for Bluetooth access and
    /// waits for the answer, so reads run off the main thread.
    static func read() async -> (on: Bool?, devices: [BluetoothDevice]) {
        await blocking {
            let on = IOBluetoothHostController.default().map { $0.powerState == kBluetoothHCIPowerStateON }
            return (on, on == true ? devices() : [])
        }
    }

    private nonisolated static func devices() -> [BluetoothDevice] {
        uniqueDevices(((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).map { device in
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

/// Dark Mode, through SkyLight, where System Settings switches it. Unlike System Events, it needs no Automation grant.
enum Appearance {
    private static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let get = systemFunction(framework, "SLSGetAppearanceThemeLegacy", as: (@convention(c) () -> Bool).self)
    /// The second argument posts the change to running apps.
    private static let set = systemFunction(framework, "SLSSetAppearanceThemeNotifying", as: (@convention(c) (Bool, Bool) -> Void).self)

    static func isDark() -> Bool? {
        get?()
    }

    static func setDark(_ dark: Bool) {
        set?(dark, true)
    }
}

/// The native menu bar's opacity, through SkyLight, as yabai's `menubar_opacity` sets it. At 0 it never shows through
/// the glass when the pointer reaches the top edge, and ignores the mouse. It lasts only while this process runs, so
/// the native bar comes back if the bar quits or crashes.
enum NativeMenuBar {
    private nonisolated static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private nonisolated static let connection = systemFunction(framework, "SLSMainConnectionID", as: (@convention(c) () -> Int32).self)
    private static let set = systemFunction(framework, "SLSSetMenuBarInsetAndAlpha", as: (@convention(c) (Int32, Double, Double, Float) -> Int32).self)

    private nonisolated static let setShown = systemFunction(framework, "SLSSetMenuBarVisibilityOverrideOnDisplay",
                                                             as: (@convention(c) (Int32, CGDirectDisplayID, Bool) -> Void).self)

    static func setAlpha(_ alpha: Float) {
        guard let connection, let set else { return }
        _ = set(connection(), 0, 1, alpha)
    }

    /// Keeps the menu bar shown while menu bar auto-hide would hide it, or lets it hide again.
    nonisolated static func setShown(_ shown: Bool) {
        guard let connection, let setShown else { return }
        setShown(connection(), CGMainDisplayID(), shown)
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

/// Night Shift, through CoreBrightness's CBBlueLightClient, which Control Center uses.
enum NightShift {
    private static let client = privateObject("CoreBrightness", "CBBlueLightClient")
    private static let status = method(client, "getBlueLightStatus:", as: (@convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool).self)
    private static let enable = method(client, "setEnabled:", as: (@convention(c) (NSObject, Selector, Bool) -> Bool).self)

    static func isOn() -> Bool? {
        guard let client, let status else { return nil }
        // The status struct is about 40 bytes: BOOL active, BOOL enabled, BOOL sunSchedulePermitted, int mode, the
        // schedule, flags. Enabled is what Control Center's toggle shows.
        var buffer = [UInt8](repeating: 0, count: 128)
        guard status(client, NSSelectorFromString("getBlueLightStatus:"), &buffer) else { return nil }
        return buffer[1] != 0
    }

    static func setOn(_ on: Bool) {
        guard let client, let enable else { return }
        _ = enable(client, NSSelectorFromString("setEnabled:"), on)
    }
}

/// macOS's "Turn Do Not Disturb On/Off" shortcut (symbolic hotkey 175), pressed with a posted key event. It switches
/// Focus without opening Control Center, which still shows its own banner. Unless the user bound it, the shortcut gets
/// ⌃⌥⇧⌘ plus a letter no other system shortcut uses, only for the moment of the press. SkyLight keeps that binding in
/// the login session and never writes the user's keyboard shortcut preferences.
enum DoNotDisturbShortcut {
    private nonisolated static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private nonisolated static let get = systemFunction(framework, "CGSGetSymbolicHotKeyValue",
        as: (@convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32).self)
    private nonisolated static let set = systemFunction(framework, "CGSSetSymbolicHotKeyValue", as: (@convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32).self)
    private nonisolated static let isEnabled = systemFunction(framework, "CGSIsSymbolicHotKeyEnabled", as: (@convention(c) (Int32) -> Bool).self)
    private nonisolated static let setEnabled = systemFunction(framework, "CGSSetSymbolicHotKeyEnabled", as: (@convention(c) (Int32, Bool) -> Int32).self)
    private nonisolated static let id: Int32 = 175
    private nonisolated static let unbound: UInt16 = 0xFFFF
    private nonisolated static let hyper: UInt32 = 0x1E0000
    /// D, F, J and K as (character, virtual key code).
    private nonisolated static let letters: [(UInt16, UInt16)] = [(100, 2), (102, 3), (106, 38), (107, 40)]

    /// Presses the shortcut, and returns false when SkyLight lacks the calls or every candidate combo is taken.
    nonisolated static func press() -> Bool {
        guard let get, let set, let isEnabled, let setEnabled else { return false }
        func value(_ id: Int32) -> (char: UInt16, key: UInt16, mods: UInt32)? {
            var char: UInt16 = 0, key: UInt16 = 0, mods: UInt32 = 0
            return get(id, &char, &key, &mods) == 0 ? (char, key, mods) : nil
        }
        let old = value(id) ?? (unbound, unbound, 0), wasEnabled = isEnabled(id)
        let rebound = !wasEnabled || old.key == unbound
        var combo = (old.key, old.mods)
        if rebound {
            let taken = Set((0..<512).compactMap { other in isEnabled(other) ? value(other).flatMap { $0.mods == hyper ? $0.key : nil } : nil })
            guard let (char, key) = letters.first(where: { !taken.contains($0.1) }) else { return false }
            _ = set(id, char, key, hyper)
            _ = setEnabled(id, true)
            combo = (key, hyper)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.0, keyDown: down) else { return false }
            event.flags = CGEventFlags(rawValue: UInt64(combo.1))
            event.post(tap: .cghidEventTap)
        }
        if rebound {
            // WindowServer reads the event after the post returns, and needs the binding until then.
            usleep(200_000)
            _ = set(id, old.char, old.key, old.mods)
            _ = setEnabled(id, wasEnabled)
        }
        return true
    }
}

/// The real Control Center, through Accessibility: its status items, and its panel for the one control with no API.
enum SystemControlCenter {
    nonisolated static let controlCenter = "com.apple.menuextra.controlcenter"
    /// Shown while a Focus is on, unless the user set it to always show in the menu bar.
    nonisolated static let focus = "com.apple.menuextra.focusmode"

    private nonisolated static var pid: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
    }

    /// Control Center's status items by identifier, empty without Accessibility access.
    nonisolated static func extras() -> [String: AXUIElement] {
        guard AXIsProcessTrusted(), let pid else { return [:] }
        return Dictionary(MenuExtras.items(pid: pid).compactMap { item in AX.string(item, "AXIdentifier").map { ($0, item) } }) { first, _ in first }
    }

    /// Whether a Focus is on, read from its status item. Nil without Accessibility access. The Focus database itself
    /// needs Full Disk Access, and the DoNotDisturb framework refuses clients without Apple's entitlement.
    static func focusIsOn() -> Bool? {
        let items = extras()
        return items.isEmpty ? nil : items[focus] != nil
    }

    /// Switches Do Not Disturb with its keyboard shortcut; donotdisturbd rejects clients without Apple's entitlement.
    /// Without SkyLight's shortcut calls it presses in Control Center instead: while a Focus is on, its own status item
    /// opens a small panel of modes, otherwise the full Control Center opens, then its Focus module. It blocks until
    /// done, and returns false when nothing was switched.
    nonisolated static func toggleFocus() -> Bool {
        if DoNotDisturbShortcut.press() { return true }
        guard let (app, item) = openPanel(extras()[focus] != nil ? focus : controlCenter) else { return false }
        defer { close(app, item) }
        func isMode(_ element: AXUIElement) -> Bool { AX.string(element, "AXIdentifier")?.hasPrefix("focus-mode-activity-") == true }
        if let module = waitFor(app, { isMode($0) || AX.string($0, "AXIdentifier") == "controlcenter-focus-modes" }).first, !isMode(module) {
            AX.press(module)
        }
        let modes = waitFor(app, isMode)
        let active = modes.first { AX.attribute($0, kAXValueAttribute) as? Int == 1 }
        let target = active ?? modes.first { AX.string($0, "AXIdentifier")?.hasSuffix(".donotdisturb.mode.default") == true }
        guard let target else { return false }
        return AX.press(target)
    }

    /// Opens the real Control Center on one of its modules, as a click on the module would, and leaves it open for
    /// the user: Screen Mirroring lists the displays to mirror to, Sound lists every output, AirPlay receivers
    /// included. It blocks until the module has opened, and returns false when it did not, or without Accessibility.
    nonisolated static func showModule(_ id: String) -> Bool {
        guard let (app, _) = openPanel() else { return false }
        guard let module = waitFor(app, { AX.string($0, "AXIdentifier") == id }).first else { return false }
        return AX.press(module)
    }

    /// Opens the real Control Center on its main view and leaves it open. False without Accessibility access.
    nonisolated static func show() -> Bool {
        openPanel() != nil
    }

    /// Opens the panel of Control Center's status item `id` (its main view by default), and returns Control Center and
    /// the item. Nil without Accessibility access.
    private nonisolated static func openPanel(_ id: String = controlCenter) -> (app: AXUIElement, item: AXUIElement)? {
        guard let item = extras()[id], let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        close(app, item)
        // With menu bar auto-hide on, the status item sits above the screen, where a press opens nothing. The panel
        // stays open once the menu bar hides again.
        NativeMenuBar.setShown(true)
        defer { NativeMenuBar.setShown(false) }
        for _ in 0..<50 where position(item).y < 0 { usleep(10_000) }
        // The status item keeps its own idea of whether the panel is open, which drifts when the panel closes by
        // itself; then the first press only resets it.
        for _ in 0..<2 where windows(app).isEmpty {
            AX.press(item)
            for _ in 0..<40 where windows(app).isEmpty { usleep(10_000) }
        }
        return (app, item)
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

    /// The panel's controls matching `match`, once they appear, within 1.5s.
    private nonisolated static func waitFor(_ app: AXUIElement, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
        for _ in 0..<150 {
            let found = controls(app).filter(match)
            if !found.isEmpty { return found }
            usleep(10_000)
        }
        return []
    }

    /// Presses the status item until the panel is gone. From a module's detail view a press goes back to the main
    /// view, and the panel takes a moment to close, so each press waits for one or the other before the next.
    private nonisolated static func close(_ app: AXUIElement, _ item: AXUIElement) {
        func mainView() -> Bool { controls(app).contains { AX.string($0, "AXIdentifier") == "controlcenter-focus-modes" } }
        for _ in 0..<3 where !windows(app).isEmpty {
            let fromDetail = !mainView()
            AX.press(item)
            for _ in 0..<100 where !windows(app).isEmpty && !(fromDetail && mainView()) { usleep(10_000) }
        }
    }
}

enum AirDrop {
    static func mode() -> AirDropMode? {
        (CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String).flatMap(AirDropMode.init)
    }
}
