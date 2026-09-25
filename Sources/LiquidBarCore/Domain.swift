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
    public var percent: Int
    public var charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }
}

public struct VolumeState: Equatable, Sendable {
    public var level: Int  // 0...100
    public var muted: Bool

    public init(level: Int, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}

public enum NetworkState: Equatable, Sendable {
    case wifi, wired, offline
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
        "clock": "open -a 'Notification Center'",
        "date": "open -a Calendar",
    ]

    public init() {}
}

public enum Tint: Equatable, Sendable {
    case normal, green, yellow, red
}

extension BatteryState {
    public var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 90...: return "battery.100percent"
        case 70..<90: return "battery.75percent"
        case 50..<70: return "battery.50percent"
        case 30..<50: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    public var tint: Tint {
        if charging { return .green }
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

extension NetworkState {
    public var symbol: String {
        switch self {
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
