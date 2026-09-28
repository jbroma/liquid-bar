import LiquidBarCore
import Testing

@Test func tileLabels() {
    #expect(ControlTile.allCases.map { $0.label(ControlState(airDrop: .contactsOnly)) }
        == ["Bluetooth", "Contacts", "Focus", "Mirroring", "Dark Mode", "Night Shift", "Screenshot"])
    #expect(ControlTile.airDrop.label(ControlState(airDrop: .everyone)) == "Everyone")
    #expect(ControlTile.airDrop.label(ControlState(airDrop: .off)) == "AirDrop")
    #expect(ControlTile.airDrop.label(ControlState()) == "AirDrop")
}

@Test func tilesAreOnOnlyWhenTheirControlIs() {
    let state = ControlState(bluetooth: true, focus: nil, airDrop: .off, darkMode: true, nightShift: false)
    #expect(ControlTile.allCases.filter { $0.isOn(state) } == [.bluetooth, .darkMode])
    #expect(ControlTile.airDrop.isOn(ControlState(airDrop: .everyone)))
}

@Test func airDropModeFromSharingd() {
    #expect(AirDropMode(rawValue: "Everyone") == .everyone)
    #expect(AirDropMode(rawValue: "Contacts Only") == .contactsOnly)
    #expect(AirDropMode(rawValue: "Off") == .off)
    #expect(AirDropMode(rawValue: "everyone") == nil)
}

@Test func bluetoothSymbols() {
    // Classes as this Mac's paired devices report them.
    #expect(bluetoothSymbol(name: "Sam’s AirPods Pro", major: 4, minor: 6) == "airpodspro")
    #expect(bluetoothSymbol(name: "Living Room Soundbar", major: 4, minor: 5) == "hifispeaker")
    #expect(bluetoothSymbol(name: "WH-1000XM5", major: 4, minor: 6) == "headphones")
    #expect(bluetoothSymbol(name: "Test iPhone", major: 2, minor: 3) == "iphone")
    #expect(bluetoothSymbol(name: "Test iPhone", major: 0, minor: 0) == "iphone")
    #expect(bluetoothSymbol(name: "Magic Keyboard", major: 5, minor: 0x10) == "keyboard")
    #expect(bluetoothSymbol(name: "Magic Mouse", major: 5, minor: 0x20) == "computermouse")
    #expect(bluetoothSymbol(name: "Tag", major: 7, minor: 0) == "dot.radiowaves.left.and.right")
}

@Test func bluetoothBatteryPicksTheReportedFigure() {
    #expect(bluetoothBattery(single: 80, left: 0, right: 0, combined: 0) == 80)
    #expect(bluetoothBattery(single: 0, left: 100, right: 90, combined: 95) == 90)
    #expect(bluetoothBattery(single: 0, left: 0, right: 70, combined: 0) == 70)
    #expect(bluetoothBattery(single: 0, left: 0, right: 0, combined: 60) == 60)
    #expect(bluetoothBattery(single: 0, left: 0, right: 0, combined: 0) == nil)
}

@Test func duplicatePairingRecordsShowOnce() {
    func device(_ id: String, _ name: String, connected: Bool = false) -> BluetoothDevice {
        BluetoothDevice(id: id, name: name, connected: connected, battery: nil, symbol: "hifispeaker")
    }
    // What IOBluetooth lists on this Mac: the soundbar twice.
    let paired = [device("02-00-00-00-00-01", "Living Room Soundbar"), device("02-00-00-00-00-03", "Sam’s AirPods Pro"),
                  device("02-00-00-00-00-02", "Living Room Soundbar", connected: true), device("02-00-00-00-00-04", "Test iPhone")]
    #expect(uniqueDevices(paired).map(\.id) == ["02-00-00-00-00-02", "02-00-00-00-00-03", "02-00-00-00-00-04"])
}
