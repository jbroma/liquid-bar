import Foundation

public struct Workspace: Identifiable, Equatable, Sendable, Codable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct WorkspaceState: Equatable, Sendable {
    public var focused: String?
    public var mode: String
    public internal(set) var windows: [Window]
    /// Window IDs, most recently focused first.
    public var recency: [Int]

    public init(focused: String? = nil, mode: String = "main", windows: [Window] = [], recency: [Int] = []) {
        self.focused = focused
        self.mode = mode
        self.windows = windows
        self.recency = recency
    }
}

public struct BatteryState: Equatable, Sendable {
    public enum Power: Equatable, Sendable {
        /// Minutes are nil while macOS is still estimating.
        case battery(minutesLeft: Int?)
        case charging(minutesToFull: Int?)
        /// On AC but not charging: full, or held by optimized charging.
        case pluggedIn
    }

    public var percent: Int
    public var power: Power

    public init(percent: Int, power: Power) {
        self.percent = percent
        self.power = power
    }

    public var onAC: Bool {
        if case .battery = power { false } else { true }
    }
}

public struct VolumeState: Equatable, Sendable {
    public var level: Int  // 0...100
    public var muted: Bool
    public var device: String

    public init(level: Int, muted: Bool, device: String = "") {
        self.level = level
        self.muted = muted
        self.device = device
    }
}

public struct NetworkState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case wifi, wired, offline }

    public var kind: Kind
    /// BSD name of the primary interface, like "en0".
    public var interface: String?

    public init(kind: Kind, interface: String? = nil) {
        self.kind = kind
        self.interface = interface
    }
}

public struct ScriptWidget: Equatable, Hashable, Sendable, Codable {
    public var script: String
    public var symbol: String?
    public var interval: Double?
    public var on: [String]?
    public var click: String?

    public init(script: String, symbol: String? = nil, interval: Double? = nil, on: [String]? = nil, click: String? = nil) {
        self.script = script
        self.symbol = symbol
        self.interval = interval
        self.on = on
        self.click = click
    }
}

public enum Widget: Equatable, Hashable, Sendable {
    case apple, workspaces, nowPlaying, volume, wifi, battery, controlCenter, clock
    case script(ScriptWidget)

    /// The key used in `clicks`; script widgets carry their own `click`.
    public var name: String {
        switch self {
        case .apple: "apple"
        case .workspaces: "workspaces"
        case .nowPlaying: "nowPlaying"
        case .volume: "volume"
        case .wifi: "wifi"
        case .battery: "battery"
        case .controlCenter: "controlCenter"
        case .clock: "clock"
        case .script: "script"
        }
    }
}

public struct Config: Equatable, Sendable {
    public var margin: Double = 10
    public var workspaces: [Workspace] = (1...9).map { Workspace(id: String($0)) }
    public var left: [Widget] = [.apple, .workspaces]
    public var right: [Widget] = [.nowPlaying, .volume, .wifi, .battery, .controlCenter, .clock]
    public var clicks: [String: String] = [
        "volume": "open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'",
        "wifi": "open 'x-apple.systempreferences:com.apple.Network-Settings.extension'",
        "battery": "open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'",
    ]

    public init() {}
}

public enum Tint: Equatable, Sendable {
    case normal, green, yellow, red
}

extension BatteryState {
    public var symbol: String {
        if onAC { return "battery.100percent.bolt" }
        // Nearest of the five drawn levels, so 26% shows a quarter, not an empty battery.
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    public var tint: Tint {
        if onAC { return .green }
        if percent <= 20 { return .red }
        if percent <= 40 { return .yellow }
        return .normal
    }
}

extension VolumeState {
    public var symbol: String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 30 { return "speaker.wave.1.fill" }
        if level < 60 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// The level after `steps` scroll steps of 2 points each, clamped to 0...100.
    public func stepped(_ steps: Int) -> Int {
        min(100, max(0, level + steps * 2))
    }
}

extension BatteryState {
    /// "3:12 left", "Charging, 1:05 to full", "Charged".
    public var detail: String {
        switch power {
        case .battery(let minutes?): "\(durationText(minutes)) left"
        case .battery(nil): "Estimating time left"
        case .charging(let minutes?): "Charging, \(durationText(minutes)) to full"
        case .charging(nil): "Charging"
        case .pluggedIn: percent >= 95 ? "Charged" : "Not charging"
        }
    }
}

/// 192 -> "3:12".
public func durationText(_ minutes: Int) -> String {
    "\(minutes / 60):" + String(format: "%02d", minutes % 60)
}

/// "2.4 MB/s", "120 KB/s": decimal units like Activity Monitor, one decimal below 10.
public func throughputText(_ bytesPerSecond: Double) -> String {
    let units = ["KB/s", "MB/s", "GB/s"]
    var value = bytesPerSecond / 1000
    var unit = 0
    while value >= 1000, unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    let digits = unit > 0 && value < 10 ? "%.1f" : "%.0f"
    return String(format: digits, value) + " " + units[unit]
}

/// Wi-Fi signal as 0...3 bars from RSSI in dBm.
public func signalBars(rssi: Int) -> Int {
    if rssi >= -60 { return 3 }
    if rssi >= -70 { return 2 }
    if rssi >= -80 { return 1 }
    return 0
}

extension NetworkState {
    public var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .wired: "network"
        case .offline: "wifi.slash"
        }
    }
}

/// "19:27".
public func clockText(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "HH:mm", timeZone)
}

/// "Saturday 26 September 2026".
public func fullDateText(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "EEEE d MMMM y", timeZone)
}

private func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = pattern
    return formatter.string(from: date)
}

/// Six full weeks covering the month that contains `date`, starting on the calendar's first weekday,
/// so the grid never changes height between months.
public func monthGrid(for date: Date, calendar: Calendar) -> [Date] {
    let month = calendar.dateInterval(of: .month, for: date)!.start
    let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    let start = calendar.date(byAdding: .day, value: -lead, to: month)!
    return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
}

/// Modifier keys of a menu shortcut as the Accessibility API reports them in `AXMenuItemCmdModifiers`:
/// Command is implied unless bit 3 is set; bits 0, 1 and 2 add Shift, Option and Control.
public struct ShortcutModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)

    public init(axMask: Int) {
        var modifiers: ShortcutModifiers = axMask & 8 == 0 ? .command : []
        if axMask & 1 != 0 { modifiers.insert(.shift) }
        if axMask & 2 != 0 { modifiers.insert(.option) }
        if axMask & 4 != 0 { modifiers.insert(.control) }
        self = modifiers
    }
}
