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
