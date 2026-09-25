import Foundation
import LiquidBarCore
import Testing

@Test func batteryFollowsTodaysColorRules() {
    let onBattery = BatteryState.Power.battery(minutesLeft: 90)
    #expect(BatteryState(percent: 51, power: onBattery).tint == .normal)
    #expect(BatteryState(percent: 40, power: onBattery).tint == .yellow)
    #expect(BatteryState(percent: 20, power: onBattery).tint == .red)
    #expect(BatteryState(percent: 12, power: .charging(minutesToFull: 80)).tint == .green)
    #expect(BatteryState(percent: 80, power: .pluggedIn).tint == .green)
    #expect(BatteryState(percent: 49, power: onBattery).symbol == "battery.25percent")
    #expect(BatteryState(percent: 95, power: onBattery).symbol == "battery.100percent")
    #expect(BatteryState(percent: 12, power: .charging(minutesToFull: nil)).symbol == "battery.100percent.bolt")
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
    #expect(dateText(date, timeZone: utc) == "Fri 25 Sep")
    #expect(longDateText(date, timeZone: utc) == "Friday 25 September")
    #expect(dateText(Date(timeIntervalSince1970: 1_780_000_000), timeZone: utc) == "Thu 28 May")
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
    #expect(ShortcutModifiers(axMask: 8) == [])
}
