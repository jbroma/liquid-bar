import Foundation

/// What the Control Center dropdown shows, read from the system each time it opens. A nil control is one this Mac or
/// macOS does not offer, and its tile says so instead of acting.
public struct ControlState: Equatable, Sendable {
    /// The built-in display's brightness, 0...1.
    public var brightness: Double?
    /// The built-in keyboard's backlight, 0...1.
    public var keyboard: Double?
    /// Whether the Bluetooth controller is powered.
    public var bluetooth: Bool?
    public var devices: [BluetoothDevice]
    public var focus: Bool?
    public var airDrop: AirDropMode?
    public var darkMode: Bool?
    public var nightShift: Bool?

    public init(brightness: Double? = nil, keyboard: Double? = nil, bluetooth: Bool? = nil, devices: [BluetoothDevice] = [],
                focus: Bool? = nil, airDrop: AirDropMode? = nil, darkMode: Bool? = nil, nightShift: Bool? = nil) {
        self.brightness = brightness
        self.keyboard = keyboard
        self.bluetooth = bluetooth
        self.devices = devices
        self.focus = focus
        self.airDrop = airDrop
        self.darkMode = darkMode
        self.nightShift = nightShift
    }
}

/// Who can see this Mac in AirDrop, as sharingd stores it in `DiscoverableMode`. The raw value is also the menu
/// title, which is what macOS 26 Control Center's AirDrop uses.
public enum AirDropMode: String, CaseIterable, Sendable {
    case off = "Off"
    case contactsOnly = "Contacts Only"
    case everyone = "Everyone"

    /// The mode a click on the AirDrop circle switches to: off from any other mode, otherwise the last visible mode.
    public func toggled(last: AirDropMode?) -> AirDropMode {
        guard self == .off else { return .off }
        return last.flatMap { $0 == .off ? nil : $0 } ?? .contactsOnly
    }
}

/// The Control Center controls.
public enum ControlTile: CaseIterable, Sendable {
    case bluetooth, airDrop, focus, darkMode, nightShift, screenshot

    /// Whether the control shows as switched on. Controls that only open something are never on.
    public func isOn(_ state: ControlState) -> Bool {
        switch self {
        case .bluetooth: state.bluetooth == true
        case .airDrop: state.airDrop.map { $0 != .off } ?? false
        case .focus: state.focus == true
        case .darkMode: state.darkMode == true
        case .nightShift: state.nightShift == true
        case .screenshot: false
        }
    }

    public var name: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .airDrop: "AirDrop"
        case .focus: "Focus"
        case .darkMode: "Dark Mode"
        case .nightShift: "Night Shift"
        case .screenshot: "Screenshot"
        }
    }

    /// The state line under the name, for the controls whose circle alone cannot say it: AirDrop has three modes.
    /// Nil when the control has none or its state could not be read.
    public func detail(_ state: ControlState) -> String? {
        switch self {
        case .bluetooth: state.bluetooth.map { $0 ? "On" : "Off" }
        case .airDrop: state.airDrop?.rawValue
        case .focus: state.focus.map { $0 ? "On" : "Off" }
        case .darkMode, .nightShift, .screenshot: nil
        }
    }
}

/// A paired Bluetooth device.
public struct BluetoothDevice: Identifiable, Equatable, Sendable {
    /// Its address, like "02-00-00-00-00-03".
    public var id: String
    public var name: String
    public var connected: Bool
    /// Charge in percent, for devices that report it.
    public var battery: Int?
    public var symbol: String

    public init(id: String, name: String, connected: Bool, battery: Int?, symbol: String) {
        self.id = id
        self.name = name
        self.connected = connected
        self.battery = battery
        self.symbol = symbol
    }
}

/// The SF Symbol for a Bluetooth device, from its name and its major and minor device class.
public func bluetoothSymbol(name: String, major: UInt32, minor: UInt32) -> String {
    if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
    if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
    if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
    // Apple's phones and tablets often report no device class.
    if name.localizedCaseInsensitiveContains("iPhone") { return "iphone" }
    if name.localizedCaseInsensitiveContains("iPad") { return "ipad" }
    switch major {
    case 1: return "laptopcomputer"
    case 2: return "iphone"
    // Audio: headphones and headsets, anything else is a speaker.
    case 4: return [1, 2, 6].contains(minor) ? "headphones" : "hifispeaker"
    // Peripherals: bit 4 of the minor class is a keyboard, bit 5 a pointer.
    case 5: return minor & 0x10 != 0 ? "keyboard" : minor & 0x20 != 0 ? "computermouse" : "gamecontroller"
    default: return "dot.radiowaves.left.and.right"
    }
}

/// A device's charge from IOBluetooth's battery fields, which are 0 when not reported: its single battery, or the
/// lower earbud, or the combined figure.
public func bluetoothBattery(single: Int, left: Int, right: Int, combined: Int) -> Int? {
    if single > 0 { return single }
    if let bud = [left, right].filter({ $0 > 0 }).min() { return bud }
    return combined > 0 ? combined : nil
}

/// One row per device name, connected devices first, otherwise in paired order. macOS can keep a second pairing record
/// for the same device, as IOBluetooth lists it; the connected record wins.
public func deviceRows(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
    var rows: [BluetoothDevice] = []
    for device in devices {
        if let index = rows.firstIndex(where: { $0.name == device.name }) {
            if device.connected && !rows[index].connected { rows[index] = device }
        } else {
            rows.append(device)
        }
    }
    return rows.filter(\.connected) + rows.filter { !$0.connected }
}
