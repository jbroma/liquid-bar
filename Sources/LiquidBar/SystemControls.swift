import AppKit
import ApplicationServices
import IOBluetooth
import LiquidBarCore

// One boundary per subsystem behind the Control Center dropdown. Each reads nil and does nothing when this macOS
// lacks what it needs, so a missing private symbol costs a tile, never a crash.

/// A C function from a system framework, or nil when this macOS does not have it.
private func systemFunction<T>(_ path: String, _ name: String, as type: T.Type) -> T? {
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
        (client?.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber])?.first?.uint64Value
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
        await Task.detached {
            let on = IOBluetoothHostController.default().map { $0.powerState == kBluetoothHCIPowerStateON }
            return (on, on == true ? devices() : [])
        }.value
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
        await Task.detached {
            guard let device = IOBluetoothDevice(addressString: address) else { return }
            if device.isConnected() { device.closeConnection() } else { device.openConnection() }
        }.value
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

/// The real Control Center, through Accessibility: its status items, and its panel for the one control with no API.
enum SystemControlCenter {
    nonisolated static let controlCenter = "com.apple.menuextra.controlcenter"
    /// Shown while a Focus is on, unless the user set it to always show in the menu bar.
    static let focus = "com.apple.menuextra.focusmode"

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

    /// Turns the active Focus off, or Do Not Disturb on, by pressing through Control Center's Focus module; nothing
    /// else can switch Focus. Control Center opens for a moment. It blocks until Control Center has closed again, and
    /// returns whether a Focus is on now, or nil when Control Center did not show its Focus module.
    nonisolated static func toggleFocus() -> Bool? {
        guard let (app, item) = openPanel() else { return nil }
        defer { close(app, item) }
        func isMode(_ element: AXUIElement) -> Bool { AX.string(element, "AXIdentifier")?.hasPrefix("focus-mode-activity-") == true }
        if let module = waitFor(app, { isMode($0) || AX.string($0, "AXIdentifier") == "controlcenter-focus-modes" }).first, !isMode(module) {
            AX.press(module)
        }
        let modes = waitFor(app, isMode)
        let active = modes.first { AX.attribute($0, kAXValueAttribute) as? Int == 1 }
        let target = active ?? modes.first { AX.string($0, "AXIdentifier")?.hasSuffix(".donotdisturb.mode.default") == true }
        guard let target else { return nil }
        AX.press(target)
        return active == nil
    }

    /// Opens the real Control Center on one of its modules, as a click on the module would, and leaves it open for
    /// the user: Screen Mirroring lists the displays to mirror to, Sound lists every output, AirPlay receivers
    /// included. It blocks until the module has opened, and returns false when it did not, or without Accessibility.
    nonisolated static func showModule(_ id: String) -> Bool {
        guard let (app, _) = openPanel() else { return false }
        guard let module = waitFor(app, { AX.string($0, "AXIdentifier") == id }).first else { return false }
        return AX.press(module)
    }

    /// Opens Control Center's panel on its main view, and returns Control Center and its status item. Nil without
    /// Accessibility access.
    private nonisolated static func openPanel() -> (app: AXUIElement, item: AXUIElement)? {
        guard let item = extras()[controlCenter], let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        close(app, item)
        // The status item keeps its own idea of whether the panel is open, which drifts when the panel closes by
        // itself; then the first press only resets it.
        for _ in 0..<2 where windows(app).isEmpty {
            AX.press(item)
            for _ in 0..<40 where windows(app).isEmpty { usleep(10_000) }
        }
        return (app, item)
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
