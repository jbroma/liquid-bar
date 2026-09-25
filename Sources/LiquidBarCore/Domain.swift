import Foundation

public struct Workspace: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var symbol: String

    public init(id: String, symbol: String) {
        self.id = id
        self.symbol = symbol
    }
}

public struct WorkspaceState: Equatable, Sendable {
    public var focused: String?
    public var occupied: Set<String>
    public var mode: String

    public init(focused: String? = nil, occupied: Set<String> = [], mode: String = "main") {
        self.focused = focused
        self.occupied = occupied
        self.mode = mode
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
    case apple, workspaces, volume, wifi, battery, clock, date
    case script(ScriptWidget)

    /// The key used in `clicks`; script widgets carry their own `click`.
    public var name: String {
        switch self {
        case .apple: "apple"
        case .workspaces: "workspaces"
        case .volume: "volume"
        case .wifi: "wifi"
        case .battery: "battery"
        case .clock: "clock"
        case .date: "date"
        case .script: "script"
        }
    }
}

public struct Config: Equatable, Sendable {
    public var height: Double = 40
    public var margin: Double = 10
    public var workspaces: [Workspace] = [
        .init(id: "1", symbol: "terminal"),
        .init(id: "2", symbol: "globe"),
        .init(id: "3", symbol: "apple.terminal"),
        .init(id: "4", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "5", symbol: "folder.fill"),
        .init(id: "6", symbol: "note.text"),
        .init(id: "7", symbol: "number"),
        .init(id: "8", symbol: "gamecontroller.fill"),
        .init(id: "9", symbol: "music.note"),
    ]
    public var left: [Widget] = [.apple, .workspaces]
    public var right: [Widget] = [.volume, .wifi, .battery, .clock, .date]
    public var clicks: [String: String] = [
        "volume": "open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'",
        "wifi": "open 'x-apple.systempreferences:com.apple.Network-Settings.extension'",
        "battery": "open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'",
        // `open -a 'Notification Center'` fails on macOS 26; clicking the clock menu extra needs Accessibility access.
        "clock": #"osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose value of attribute "AXIdentifier" is "com.apple.menuextra.clock")'"#,
        "date": "open -a Calendar",
    ]

    public init() {}
}

public enum Tint: Equatable, Sendable {
    case normal, green, yellow, red
}

extension BatteryState {
    public var symbol: String {
        if onAC { return "battery.100percent.bolt" }
        switch percent {
        case 90...: return "battery.100percent"
        case 70..<90: return "battery.75percent"
        case 50..<70: return "battery.50percent"
        case 30..<50: return "battery.25percent"
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

/// "19:27", like `date '+%H:%M'`.
public func clockText(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "HH:mm", timeZone)
}

/// "Fri. 25 Sep.", like `date '+%a. %d %b.'`.
public func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "EEE. dd MMM.", timeZone)
}

private func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = pattern
    return formatter.string(from: date)
}
