import AppKit
import ApplicationServices
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

/// The real Control Center's status items, pressed through Accessibility.
enum SystemControlCenter {
    static let controlCenter = "com.apple.menuextra.controlcenter"
    static let screenMirroring = "com.apple.menuextra.screen-mirroring"

    /// Control Center's status items by identifier, empty without Accessibility access.
    nonisolated static func extras() -> [String: AXUIElement] {
        guard AXIsProcessTrusted(), let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        else { return [:] }
        return Dictionary(MenuExtras.items(pid: pid).compactMap { item in AppMenus.string(item, "AXIdentifier").map { ($0, item) } }) { first, _ in first }
    }

    /// Opens the status item's own panel or menu. False when there is no such item or no Accessibility access.
    static func open(_ id: String) -> Bool {
        guard let item = extras()[id] else { return false }
        MenuExtras.press(item)
        return true
    }
}

enum AirDrop {
    static func mode() -> AirDropMode? {
        (CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String).flatMap(AirDropMode.init)
    }

    static func openWindow() {
        shell("open -b com.apple.finder.Open-AirDrop")
    }
}
