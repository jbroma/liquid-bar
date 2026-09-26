import Foundation
import LiquidBarCore
import Testing

@Test func batteryHealthFromRegistry() {
    let health = BatteryHealth(registry: ["CycleCount": 490, "NominalChargeCapacity": 5116, "DesignCapacity": 6075, "PermanentFailureStatus": 0])
    #expect(health == BatteryHealth(cycleCount: 490, maxCapacity: 84, serviceRecommended: false))
    #expect(health?.condition == "Normal")
    let worn = BatteryHealth(registry: ["CycleCount": 1203, "AppleRawMaxCapacity": 3900, "DesignCapacity": 6075, "PermanentFailureStatus": 1])
    #expect(worn == BatteryHealth(cycleCount: 1203, maxCapacity: 64, serviceRecommended: true))
    #expect(worn?.condition == "Service Recommended")
    #expect(BatteryHealth(registry: ["CycleCount": 12]) == BatteryHealth(cycleCount: 12, maxCapacity: nil, serviceRecommended: false))
    #expect(BatteryHealth(registry: [:]) == nil)
}

@Test func batteryPowerSourceText() {
    #expect(BatteryState(percent: 80, power: .pluggedIn).powerSource(watts: 100) == "Power Adapter (100 W)")
    #expect(BatteryState(percent: 40, power: .charging(minutesToFull: 30)).powerSource(watts: nil) == "Power Adapter")
    #expect(BatteryState(percent: 40, power: .battery(minutesLeft: 30)).powerSource(watts: 100) == "Battery")
}

@Test func volumeSliderLevel() {
    #expect(VolumeState.level(at: 50, width: 200) == 25)
    #expect(VolumeState.level(at: 199, width: 200) == 100)
    #expect(VolumeState.level(at: -12, width: 200) == 0)
    #expect(VolumeState.level(at: 260, width: 200) == 100)
    #expect(VolumeState.level(at: 10, width: 0) == 0)
}

@Test func outputDeviceSymbols() {
    #expect(outputDeviceSymbol(transport: 0x626c_746e, name: "MacBook Pro Speakers") == "laptopcomputer")  // 'bltn'
    #expect(outputDeviceSymbol(transport: 0x626c_7565, name: "Sam's AirPods Pro") == "airpodspro")  // 'blue'
    #expect(outputDeviceSymbol(transport: 0x626c_7565, name: "WH-1000XM5") == "headphones")
    #expect(outputDeviceSymbol(transport: 0x6864_6d69, name: "LG UltraFine") == "tv")  // 'hdmi'
    #expect(outputDeviceSymbol(transport: 0x7573_6220, name: "Scarlett 2i2") == "hifispeaker")  // 'usb '
    #expect(outputDeviceSymbol(transport: 0x7669_7274, name: "Teams Audio") == "speaker.wave.2")  // 'virt'
}

@Test func dropdownStaysBetweenNotchAndScreenEdge() {
    #expect(dropdownX(center: 300, width: 260, lower: 12, upper: 640) == 170)
    #expect(dropdownX(center: 610, width: 260, lower: 12, upper: 640) == 380)
    #expect(dropdownX(center: 40, width: 260, lower: 12, upper: 640) == 12)
}
