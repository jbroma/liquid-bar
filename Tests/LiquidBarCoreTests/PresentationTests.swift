import Foundation
import LiquidBarCore
import Testing

@Test func batteryTint() {
    let onBattery = BatteryState.Power.battery(minutesLeft: 90)
    #expect(BatteryState(percent: 40, power: onBattery).tint == .normal)
    #expect(BatteryState(percent: 20, power: onBattery).tint == .red)
    #expect(BatteryState(percent: 12, power: .charging(minutesToFull: 80)).tint == .green)
    #expect(BatteryState(percent: 12, power: .pluggedIn).tint == .normal)
}

@Test func batteryFromPowerSourceDescription() {
    // Keys and values as IOPSGetPowerSourceDescription reports them on this Mac.
    let unplugged: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 96, "Max Capacity": 100,
                                    "Power Source State": "Battery Power", "Is Charging": false, "Time to Empty": 73, "Time to Full Charge": -1]
    #expect(BatteryState(description: unplugged) == BatteryState(percent: 96, power: .battery(minutesLeft: 73)))
    var estimating = unplugged
    estimating["Time to Empty"] = -1
    #expect(BatteryState(description: estimating) == BatteryState(percent: 96, power: .battery(minutesLeft: nil)))
    var charging = unplugged
    charging.merge(["Power Source State": "AC Power", "Is Charging": true, "Time to Full Charge": 25]) { $1 }
    #expect(BatteryState(description: charging) == BatteryState(percent: 96, power: .charging(minutesToFull: 25)))
    charging["Is Charging"] = false
    #expect(BatteryState(description: charging) == BatteryState(percent: 96, power: .pluggedIn))
    #expect(BatteryState(description: ["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]) == nil)
}

@Test func batteryTimeRemainingText() {
    #expect(BatteryState(percent: 51, power: .battery(minutesLeft: 192)).detail == "3:12 left")
    #expect(BatteryState(percent: 51, power: .battery(minutesLeft: 7)).detail == "0:07 left")
    #expect(BatteryState(percent: 51, power: .battery(minutesLeft: nil)).detail == "Estimating time left")
    #expect(BatteryState(percent: 40, power: .charging(minutesToFull: 65)).detail == "Charging, 1:05 to full")
    #expect(BatteryState(percent: 40, power: .charging(minutesToFull: nil)).detail == "Charging")
    #expect(BatteryState(percent: 100, power: .pluggedIn).detail == "Charged")
    #expect(BatteryState(percent: 80, power: .pluggedIn).detail == "Not charging")
}

@Test func throughputFormatting() {
    #expect(throughputText(0) == "0 KB/s")
    #expect(throughputText(420) == "0 KB/s")
    #expect(throughputText(120_400) == "120 KB/s")
    #expect(throughputText(999_000) == "999 KB/s")
    #expect(throughputText(2_430_000) == "2.4 MB/s")
    #expect(throughputText(24_300_000) == "24 MB/s")
    #expect(throughputText(1_260_000_000) == "1.3 GB/s")
}

@Test func wifiSignalBars() {
    #expect(signalBars(rssi: -45) == 3)
    #expect(signalBars(rssi: -60) == 3)
    #expect(signalBars(rssi: -61) == 2)
    #expect(signalBars(rssi: -75) == 1)
    #expect(signalBars(rssi: -90) == 0)
}

@Test func volumeSymbolAndScrollSteps() {
    #expect(VolumeState(level: 31, muted: false).symbol == "speaker.wave.2.fill")
    #expect(VolumeState(level: 31, muted: true).symbol == "speaker.slash.fill")
    #expect(VolumeState(level: 0, muted: false).symbol == "speaker.slash.fill")
    #expect(VolumeState(level: 31, muted: false).stepped(3) == 37)
    #expect(VolumeState(level: 99, muted: false).stepped(1) == 100)
    #expect(VolumeState(level: 1, muted: false).stepped(-1) == 0)
}

@Test func clockAndDateText() {
    let date = Date(timeIntervalSince1970: 1_790_364_425)  // 2026-09-25 19:27:05 UTC
    let utc = TimeZone(identifier: "UTC")!
    #expect(clockText(date, timeZone: utc) == "19:27")
    #expect(clockText(date, seconds: true, timeZone: utc) == "19:27:05")
    #expect(clockText(date, hour24: false, timeZone: utc) == "7:27 PM")
    #expect(clockText(date, hour24: false, seconds: true, timeZone: utc) == "7:27:05 PM")
    #expect(fullDateText(date, timeZone: utc) == "Friday 25 September 2026")
    #expect(fullDateText(Date(timeIntervalSince1970: 1_780_000_000), timeZone: utc) == "Thursday 28 May 2026")
}

@Test func monthGridStartsOnFirstWeekday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2  // Monday
    let day: (Date) -> String = { date in
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month!)/\(c.day!)"
    }
    let september = monthGrid(for: Date(timeIntervalSince1970: 1_790_364_425), calendar: calendar)
    #expect(september.count == 42)
    #expect(day(september[0]) == "8/31")
    #expect(day(september[1]) == "9/1")
    #expect(day(september[41]) == "10/11")
    calendar.firstWeekday = 1  // Sunday
    #expect(day(monthGrid(for: Date(timeIntervalSince1970: 1_790_364_425), calendar: calendar)[0]) == "8/30")
}

@Test func menuShortcutModifiersFromAccessibilityMask() {
    #expect(ShortcutModifiers(axMask: 0) == [.command])
    #expect(ShortcutModifiers(axMask: 1) == [.command, .shift])
    #expect(ShortcutModifiers(axMask: 3) == [.command, .shift, .option])
    #expect(ShortcutModifiers(axMask: 12) == [.control])
    #expect(ShortcutModifiers(axMask: 14) == [.option, .control])
    #expect(ShortcutModifiers(axMask: 8) == [])
}

@Test func theClockFollowsTheRegionAndItsHourSetting() {
    #expect(uses24HourClock(Locale(identifier: "en_US")) == false)
    #expect(uses24HourClock(Locale(identifier: "en_GB")) == true)
    #expect(uses24HourClock(Locale(identifier: "pl_PL")) == true)
    #expect(uses24HourClock(Locale(identifier: "en_US@rg=plzzzz")) == true)
    #expect(uses24HourClock(Locale(identifier: "en_US@hours=h23")) == true)
    #expect(uses24HourClock(Locale(identifier: "en_GB@hours=h12")) == false)
}
