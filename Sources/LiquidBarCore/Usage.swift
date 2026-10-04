import Foundation

/// The coding agents whose subscription limits the usage pill shows.
public enum UsageAgent: String, CaseIterable, Sendable {
    case claude, codex

    public var title: String {
        switch self {
        case .claude: "Claude"
        // Codex's limits are the ChatGPT plan's, and its app is named ChatGPT.
        case .codex: "ChatGPT"
        }
    }

    /// The desktop app whose icon stands for the agent.
    public var bundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    /// The account's usage page on the web.
    public var usagePage: String {
        switch self {
        case .claude: "https://claude.ai/settings/usage"
        case .codex: "https://chatgpt.com/codex/cloud/settings/usage"
        }
    }

    /// The same page in the desktop app, opened in its place when the app is installed. ChatGPT's moved there from the
    /// web, under Settings, Usage & billing.
    public var appUsagePage: String? {
        switch self {
        case .claude: nil
        case .codex: "codex://settings/usage"
        }
    }
}

/// One of a subscription's rate limits, like the 5-hour session or the week.
public struct UsageLimit: Equatable, Sendable {
    /// "Session", "Weekly", "Weekly Opus".
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date
    /// The window's length.
    public var window: TimeInterval

    public init(title: String, usedPercent: Double, resetsAt: Date, window: TimeInterval) {
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.window = window
    }

    /// How much of the window has gone by at `now`, 0...1, to compare with how much of the limit is used.
    public func elapsed(at now: Date) -> Double {
        min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / window))
    }
}

/// The title of a limit over a window of `minutes`, as Claude names its own: the 5-hour one is the session.
func limitTitle(minutes: Int) -> String {
    switch minutes {
    case 300: "Session"
    case 10080: "Weekly"
    case let minutes where minutes % 1440 == 0: "\(minutes / 1440)-Day"
    default: "\(max(1, minutes / 60))-Hour"
    }
}

/// One agent's subscription: its plan, and its limits, the shortest window first.
public struct AgentUsage: Equatable, Sendable {
    public var plan: String?
    public var limits: [UsageLimit]

    public init(plan: String?, limits: [UsageLimit]) {
        self.plan = plan
        self.limits = limits
    }

    /// The limit closest to running out, which the pill shows.
    public var tightest: UsageLimit? { limits.max { $0.usedPercent < $1.usedPercent } }
}

/// Codex's plan and rate limits from one line of its session log, which records them with every turn. A limit whose
/// window has passed counts as unused.
public func codexUsage(_ line: Data, now: Date) -> AgentUsage? {
    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let payload = json["payload"] as? [String: Any],
          let limits = (payload["rate_limits"] ?? (payload["info"] as? [String: Any])?["rate_limits"]) as? [String: Any]
    else { return nil }
    let windows = ["primary", "secondary"].compactMap { limits[$0] as? [String: Any] }.compactMap { window -> UsageLimit? in
        guard let minutes = window["window_minutes"] as? Int, let resets = window["resets_at"] as? Double else { return nil }
        let reset = Date(timeIntervalSince1970: resets)
        return UsageLimit(title: limitTitle(minutes: minutes), usedPercent: reset < now ? 0 : window["used_percent"] as? Double ?? 0, resetsAt: reset,
                          window: TimeInterval(minutes * 60))
    }
    // The shorter window first, as Claude lists them.
    return AgentUsage(plan: (limits["plan_type"] as? String)?.capitalized, limits: windows.sorted { $0.resetsAt < $1.resetsAt })
}

/// Claude's limits from its usage endpoint, `api/oauth/usage`, the numbers behind `/usage`: the 5-hour session, the
/// week, and the per-model weeks some plans have. Utilization runs from 0 to 100.
public func claudeLimits(_ data: Data) -> [UsageLimit]? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["five_hour"] != nil else { return nil }
    let week: TimeInterval = 7 * 86400
    let windows: [(String, String, TimeInterval)] = [("five_hour", "Session", 5 * 3600), ("seven_day", "Weekly", week), ("seven_day_opus", "Weekly Opus", week), ("seven_day_sonnet", "Weekly Sonnet", week)]
    return windows.compactMap { key, title, length in
        guard let window = json[key] as? [String: Any], let used = window["utilization"] as? Double,
              let resets = (window["resets_at"] as? String).flatMap(isoDate) else { return nil }
        return UsageLimit(title: title, usedPercent: used, resetsAt: resets, window: length)
    }
}

/// Claude Code's login, as it keeps it in the keychain item "Claude Code-credentials".
public struct ClaudeLogin: Equatable, Sendable {
    public var token: String
    public var expires: Date
    /// "Max 20x", "Pro".
    public var plan: String?

    public init?(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { return nil }
        self.token = token
        expires = Date(timeIntervalSince1970: (oauth["expiresAt"] as? Double ?? 0) / 1000)
        // "default_claude_max_20x" names the tier more closely than "max".
        let tier = (oauth["rateLimitTier"] as? String)?.split(separator: "_").drop { $0 != "max" && $0 != "pro" }
        plan = tier.flatMap { $0.isEmpty ? nil : $0.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
            ?? (oauth["subscriptionType"] as? String)?.capitalized
    }
}

private func isoDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
