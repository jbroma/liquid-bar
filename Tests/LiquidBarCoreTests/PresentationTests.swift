import Foundation
import LiquidBarCore
import Testing

@Test func batteryFollowsTodaysColorRules() {
    #expect(BatteryState(percent: 51, charging: false).tint == .normal)
    #expect(BatteryState(percent: 40, charging: false).tint == .yellow)
    #expect(BatteryState(percent: 20, charging: false).tint == .red)
    #expect(BatteryState(percent: 12, charging: true).tint == .green)
    #expect(BatteryState(percent: 49, charging: false).symbol == "battery.25percent")
    #expect(BatteryState(percent: 95, charging: false).symbol == "battery.100percent")
    #expect(BatteryState(percent: 12, charging: true).symbol == "battery.100percent.bolt")
}

@Test func volumeSymbolAndScrollSteps() {
    #expect(VolumeState(level: 31, muted: false).symbol == "speaker.wave.2.fill")
    #expect(VolumeState(level: 31, muted: true).symbol == "speaker.slash.fill")
    #expect(VolumeState(level: 0, muted: false).symbol == "speaker.slash.fill")
    #expect(VolumeState(level: 31, muted: false).stepped(3) == 37)
    #expect(VolumeState(level: 99, muted: false).stepped(1) == 100)
    #expect(VolumeState(level: 1, muted: false).stepped(-1) == 0)
}

@Test func clockAndDateMatchSketchyBarFormat() {
    let date = Date(timeIntervalSince1970: 1_790_364_420)  // 2026-09-25 19:27 UTC
    let utc = TimeZone(identifier: "UTC")!
    #expect(clockText(date, timeZone: utc) == "19:27")
    #expect(dateText(date, timeZone: utc) == "Fri. 25 Sep.")
    #expect(dateText(Date(timeIntervalSince1970: 1_780_000_000), timeZone: utc) == "Thu. 28 May.")
}
