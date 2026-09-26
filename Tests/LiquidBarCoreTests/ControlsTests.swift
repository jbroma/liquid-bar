import LiquidBarCore
import Testing

@Test func tileStatusLines() {
    let state = ControlState(bluetooth: true, focus: false, airDrop: .contactsOnly)
    #expect(ControlTile.allCases.map { $0.status(state) } == ["On", "Contacts Only", "Off", nil, "Unavailable", "Unavailable", nil])
    #expect(ControlTile.allCases.map { $0.status(ControlState()) } == ["Unavailable", "Unavailable", "Unavailable", nil, "Unavailable", "Unavailable", nil])
}

@Test func tilesAreOnOnlyWhenTheirControlIs() {
    let state = ControlState(bluetooth: true, focus: nil, airDrop: .off, darkMode: true, nightShift: false)
    #expect(ControlTile.allCases.filter { $0.isOn(state) } == [.bluetooth, .darkMode])
    #expect(ControlTile.airDrop.isOn(ControlState(airDrop: .everyone)))
}

@Test func wideTilesComeFirst() {
    #expect(ControlTile.allCases.filter(\.isWide) == [.bluetooth, .airDrop, .focus, .screenMirroring])
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
