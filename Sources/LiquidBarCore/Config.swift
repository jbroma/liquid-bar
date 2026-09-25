import Foundation

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
}

extension Widget: Decodable {
    static let named: [Widget] = [.apple, .workspaces, .nowPlaying, .volume, .wifi, .battery, .clock]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let widget = Self.named.first(where: { $0.name == name }) else {
                throw ConfigError(description: "unknown widget \"\(name)\"")
            }
            self = widget
        } else {
            self = .script(try container.decode(ScriptWidget.self))
        }
    }
}

extension Config {
    /// Every key is optional; missing keys keep today's defaults. `clicks` merges over the default clicks.
    public static func decode(_ data: Data) throws -> Config {
        struct Raw: Decodable {
            var height: Double?
            var margin: Double?
            var agents: Bool?
            var workspaces: [Workspace]?
            var left: [Widget]?
            var right: [Widget]?
            var clicks: [String: String]?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var config = Config()
        if let height = raw.height {
            guard (24...80).contains(height) else { throw ConfigError(description: "height must be 24...80, got \(height)") }
            config.height = height
        }
        if let margin = raw.margin {
            guard margin >= 0 else { throw ConfigError(description: "margin must be >= 0, got \(margin)") }
            config.margin = margin
        }
        if let agents = raw.agents { config.agents = agents }
        if let workspaces = raw.workspaces { config.workspaces = workspaces }
        if let left = raw.left { config.left = left }
        if let right = raw.right { config.right = right }
        config.clicks.merge(raw.clicks ?? [:]) { $1 }
        for case .script(let script) in config.left + config.right {
            if let interval = script.interval, interval < 1 {
                throw ConfigError(description: "script interval must be >= 1s, got \(interval)")
            }
        }
        return config
    }
}
