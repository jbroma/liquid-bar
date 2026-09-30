import Foundation

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
}

/// One entry of `left` or `right`: a widget name or a script object.
private struct WidgetEntry: Decodable {
    static let named: [Widget] = [.apple, .workspaces, .nowPlaying, .volume, .wifi, .battery, .controlCenter, .clock]

    let widget: Widget

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let name = try? container.decode(String.self) else {
            widget = .script(try container.decode(ScriptWidget.self))
            return
        }
        guard let named = Self.named.first(where: { $0.name == name }) else {
            throw ConfigError(description: "unknown widget \"\(name)\"")
        }
        widget = named
    }
}

extension Config {
    /// Every key is optional; missing keys keep the defaults. `clicks` merges over the default clicks.
    public static func decode(_ data: Data) throws -> Config {
        struct Raw: Decodable {
            var margin: Double?
            var workspaceSource: String?
            var clock24Hour: Bool?
            var clockSeconds: Bool?
            var batteryPercent: Bool?
            var glassStyle: String?
            var workspaces: [Workspace]?
            var left: [WidgetEntry]?
            var right: [WidgetEntry]?
            var pinned: [String]?
            var clicks: [String: String]?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var config = Config()
        if let margin = raw.margin {
            guard margin >= 0 else { throw ConfigError(description: "margin must be >= 0, got \(margin)") }
            config.margin = margin
        }
        config.workspaceSource = try choice(WorkspaceSource.self, "workspaceSource", raw.workspaceSource) ?? config.workspaceSource
        config.glassStyle = try choice(GlassStyle.self, "glassStyle", raw.glassStyle) ?? config.glassStyle
        config.clock24Hour = raw.clock24Hour ?? config.clock24Hour
        config.clockSeconds = raw.clockSeconds ?? config.clockSeconds
        config.batteryPercent = raw.batteryPercent ?? config.batteryPercent
        if let workspaces = raw.workspaces { config.workspaces = workspaces }
        if let left = raw.left { config.left = left.map(\.widget) }
        if let right = raw.right { config.right = right.map(\.widget) }
        if let pinned = raw.pinned {
            guard !pinned.contains(where: \.isEmpty) else { throw ConfigError(description: "pinned holds bundle ids, not empty strings") }
            config.pinned = pinned.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        config.clicks.merge(raw.clicks ?? [:]) { $1 }
        for case .script(let script) in config.left + config.right {
            if let interval = script.interval, interval < 1 {
                throw ConfigError(description: "script interval must be >= 1s, got \(interval)")
            }
        }
        return config
    }
}

/// The case of `T` named `name`, nil when the key is missing.
private func choice<T: RawRepresentable & CaseIterable>(_: T.Type, _ key: String, _ name: String?) throws -> T? where T.RawValue == String {
    guard let name else { return nil }
    guard let value = T(rawValue: name) else {
        let names = T.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        throw ConfigError(description: "\(key) must be one of \(names), got \"\(name)\"")
    }
    return value
}

/// A change made from the Apple menu's LiquidBar submenu.
public enum Setting: Equatable, Sendable {
    case workspaceSource(WorkspaceSource)
    case clock24Hour(Bool)
    case clockSeconds(Bool)
    case batteryPercent(Bool)
    case nowPlaying(Bool)
    case pinned(String, Bool)
    case glassStyle(GlassStyle)

    /// The config file's contents (nil when missing) with this change applied. Every other key stays as written.
    public func applied(to data: Data?) throws -> Data {
        var json: [String: Any] = [:]
        if let data {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError(description: "the config must be a JSON object")
            }
            json = object
        }
        switch self {
        case .workspaceSource(let source): json["workspaceSource"] = source.rawValue
        case .clock24Hour(let on): json["clock24Hour"] = on
        case .clockSeconds(let on): json["clockSeconds"] = on
        case .batteryPercent(let on): json["batteryPercent"] = on
        case .glassStyle(let style): json["glassStyle"] = style.rawValue
        case .nowPlaying(let on):
            let name = Widget.nowPlaying.name
            var right: [Any] = json["right"] as? [Any] ?? Config().right.map(\.name)
            let shown = right.contains { $0 as? String == name }
            // First, where the default list has it.
            if on && !shown { right.insert(name, at: 0) }
            if !on { right.removeAll { $0 as? String == name } }
            json["right"] = right
        case .pinned(let bundleID, let on):
            var pinned = json["pinned"] as? [String] ?? []
            if on && !pinned.contains(bundleID) { pinned.append(bundleID) }
            if !on { pinned.removeAll { $0 == bundleID } }
            json["pinned"] = pinned
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// Creates the config file as `{}` when missing, so there is a file to open.
public func createConfigFile(at url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: url)
}
