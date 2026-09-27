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

/// Who can see this Mac in AirDrop, as sharingd stores it in `DiscoverableMode`.
public enum AirDropMode: String, Sendable {
    case off = "Off"
    case contactsOnly = "Contacts Only"
    case everyone = "Everyone"
}

/// The Control Center tiles: wide ones with a status line, laid out two per row, then round ones.
public enum ControlTile: CaseIterable, Sendable {
    case bluetooth, airDrop, focus, screenMirroring, darkMode, nightShift, screenshot

    public var isWide: Bool {
        switch self {
        case .bluetooth, .airDrop, .focus, .screenMirroring: true
        case .darkMode, .nightShift, .screenshot: false
        }
    }

    public var title: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .airDrop: "AirDrop"
        case .focus: "Focus"
        case .screenMirroring: "Screen Mirroring"
        case .darkMode: "Dark Mode"
        case .nightShift: "Night Shift"
        case .screenshot: "Screenshot"
        }
    }

    /// Whether the tile shows as switched on. Tiles that only open something are never on.
    public func isOn(_ state: ControlState) -> Bool {
        switch self {
        case .bluetooth: state.bluetooth == true
        case .airDrop: state.airDrop.map { $0 != .off } ?? false
        case .focus: state.focus == true
        case .darkMode: state.darkMode == true
        case .nightShift: state.nightShift == true
        case .screenMirroring, .screenshot: false
        }
    }

    /// The wide tiles' status line: "On", "Contacts Only", "Unavailable", or nil for a tile that only opens something.
    public func status(_ state: ControlState) -> String? {
        func onOff(_ value: Bool?) -> String { value.map { $0 ? "On" : "Off" } ?? "Unavailable" }
        return switch self {
        case .bluetooth: onOff(state.bluetooth)
        case .airDrop: state.airDrop?.rawValue ?? "Unavailable"
        case .focus: onOff(state.focus)
        case .darkMode: onOff(state.darkMode)
        case .nightShift: onOff(state.nightShift)
        case .screenMirroring, .screenshot: nil
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

/// One row per device name, in the original order. macOS can keep a second pairing record for the same device, as
/// IOBluetooth lists it; the connected record wins.
public func uniqueDevices(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
    var rows: [BluetoothDevice] = []
    for device in devices {
        if let index = rows.firstIndex(where: { $0.name == device.name }) {
            if device.connected && !rows[index].connected { rows[index] = device }
        } else {
            rows.append(device)
        }
    }
    return rows
}
