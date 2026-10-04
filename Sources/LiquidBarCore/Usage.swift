import Foundation

/// The coding agents whose subscription usage the usage pill shows, read from their local logs.
public enum UsageAgent: String, CaseIterable, Sendable {
    case claude, codex

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The desktop app whose icon stands for the agent.
    public var bundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    /// The account's usage page.
    public var usagePage: String {
        switch self {
        case .claude: "https://claude.ai/settings/usage"
        case .codex: "https://chatgpt.com/codex/settings/usage"
        }
    }
}

/// Tokens and what they would cost at API prices.
public struct Spend: Equatable, Sendable {
    public var cost: Double
    public var tokens: Int

    public init(cost: Double = 0, tokens: Int = 0) {
        self.cost = cost
        self.tokens = tokens
    }
}

/// One of a subscription's rate limits, like the 5-hour session or the week.
public struct UsageLimit: Equatable, Sendable {
    /// "Session", "Weekly", "Weekly Opus".
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date

    public init(title: String, usedPercent: Double, resetsAt: Date) {
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
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

/// One agent's usage from its local logs.
public struct AgentUsage: Equatable, Sendable {
    public var today = Spend()
    /// Today and the six days before.
    public var week = Spend()
    /// Today's models, as ccusage names them.
    public var models: [String] = []
    /// Shortest window first.
    public var limits: [UsageLimit] = []
    public var plan: String?
    public var credits: String?

    public init() {}

    /// The limit closest to running out, which the pill shows.
    public var tightest: UsageLimit? { limits.max { $0.usedPercent < $1.usedPercent } }
}

/// Today's spend, the spend over the whole report, and today's models, from `ccusage <agent> daily --json`. Claude's
/// rows have `totalCost` and `modelsUsed`, Codex's `costUSD` and a `models` object. `today` is the local date as
/// ccusage writes it, "2026-10-04".
public func dailySpend(_ data: Data, today: String) -> (today: Spend, week: Spend, models: [String])? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let days = json["daily"] as? [[String: Any]] else { return nil }
    func spend(_ row: [String: Any]?) -> Spend {
        Spend(cost: (row?["totalCost"] ?? row?["costUSD"]) as? Double ?? 0, tokens: row?["totalTokens"] as? Int ?? 0)
    }
    let row = days.first { ($0["date"] ?? $0["period"]) as? String == today }
    let models = row?["modelsUsed"] as? [String] ?? (row?["models"] as? [String: Any]).map { $0.keys.sorted() } ?? []
    return (spend(row), spend(json["totals"] as? [String: Any]), models)
}

/// Codex's plan, rate limits and credits from one line of its session log, which records them with every turn. A
/// limit whose window has passed counts as unused.
public func codexLimits(_ line: Data, now: Date) -> (plan: String?, limits: [UsageLimit], credits: String?)? {
    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let payload = json["payload"] as? [String: Any],
          let limits = (payload["rate_limits"] ?? (payload["info"] as? [String: Any])?["rate_limits"]) as? [String: Any]
    else { return nil }
    let windows = ["primary", "secondary"].compactMap { limits[$0] as? [String: Any] }.compactMap { window -> UsageLimit? in
        guard let minutes = window["window_minutes"] as? Int, let resets = window["resets_at"] as? Double else { return nil }
        let reset = Date(timeIntervalSince1970: resets)
        return UsageLimit(title: limitTitle(minutes: minutes), usedPercent: reset < now ? 0 : window["used_percent"] as? Double ?? 0, resetsAt: reset)
    }
    let credits = (limits["credits"] as? [String: Any]).flatMap { credits -> String? in
        if credits["unlimited"] as? Bool == true { return "Unlimited" }
        guard credits["has_credits"] as? Bool == true else { return nil }
        return credits["balance"] as? String
    }
    // The shorter window first, as Claude lists them.
    return ((limits["plan_type"] as? String)?.capitalized, windows.sorted { $0.resetsAt < $1.resetsAt }, credits)
}

/// Claude's limits from its usage endpoint, `api/oauth/usage`, the numbers behind `/usage`: the 5-hour session, the
/// week, and the per-model weeks some plans have. Utilization runs from 0 to 100.
public func claudeLimits(_ data: Data) -> [UsageLimit]? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["five_hour"] != nil else { return nil }
    let windows = [("five_hour", "Session"), ("seven_day", "Weekly"), ("seven_day_opus", "Weekly Opus"), ("seven_day_sonnet", "Weekly Sonnet")]
    return windows.compactMap { key, title in
        guard let window = json[key] as? [String: Any], let used = window["utilization"] as? Double,
              let resets = (window["resets_at"] as? String).flatMap(isoDate) else { return nil }
        return UsageLimit(title: title, usedPercent: used, resetsAt: resets)
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

/// "Opus 5.5" for "claude-opus-5-5", other names as they are.
public func modelTitle(_ name: String) -> String {
    let parts = name.split(separator: "-")
    guard parts.first == "claude", parts.count >= 3 else { return name }
    let version = parts.dropFirst(2).prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
    return parts[1].capitalized + (version.isEmpty ? "" : " " + version.joined(separator: "."))
}

/// "$8.21", or "$191" from $100 up.
public func costText(_ cost: Double) -> String {
    cost >= 100 ? "$\(Int(cost.rounded()))" : String(format: "$%.2f", cost)
}

/// "820K", "20.7M", "1.98B".
public func tokenText(_ tokens: Int) -> String {
    let value = Double(tokens)
    for (limit, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where value >= limit {
        let scaled = value / limit
        return (scaled >= 100 ? String(format: "%.0f", scaled) : scaled >= 10 ? String(format: "%.1f", scaled) : String(format: "%.2f", scaled)) + suffix
    }
    return "\(tokens)"
}

private func isoDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
