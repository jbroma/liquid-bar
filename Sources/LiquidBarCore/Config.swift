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
            var workspaces: [Workspace]?
            var left: [WidgetEntry]?
            var right: [WidgetEntry]?
            var clicks: [String: String]?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var config = Config()
        if let margin = raw.margin {
            guard margin >= 0 else { throw ConfigError(description: "margin must be >= 0, got \(margin)") }
            config.margin = margin
        }
        if let name = raw.workspaceSource {
            guard let source = WorkspaceSource(rawValue: name) else {
                let names = WorkspaceSource.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
                throw ConfigError(description: "workspaceSource must be one of \(names), got \"\(name)\"")
            }
            config.workspaceSource = source
        }
        if let workspaces = raw.workspaces { config.workspaces = workspaces }
        if let left = raw.left { config.left = left.map(\.widget) }
        if let right = raw.right { config.right = right.map(\.widget) }
        config.clicks.merge(raw.clicks ?? [:]) { $1 }
        for case .script(let script) in config.left + config.right {
            if let interval = script.interval, interval < 1 {
                throw ConfigError(description: "script interval must be >= 1s, got \(interval)")
            }
        }
        return config
    }
}
