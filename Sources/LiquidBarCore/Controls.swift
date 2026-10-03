import Foundation

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
