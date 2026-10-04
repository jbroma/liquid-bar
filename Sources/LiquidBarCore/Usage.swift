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

/// Claude's current 5-hour block, which its session limit counts.
public struct UsageBlock: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var spend: Spend
    /// What the block will have cost by its end at the current rate.
    public var projectedCost: Double?

    public init(start: Date, end: Date, spend: Spend, projectedCost: Double?) {
        self.start = start
        self.end = end
        self.spend = spend
        self.projectedCost = projectedCost
    }
}

/// One of Codex's rate limits.
public struct UsageLimit: Equatable, Sendable {
    public var minutes: Int
    public var usedPercent: Double
    public var resetsAt: Date

    public init(minutes: Int, usedPercent: Double, resetsAt: Date) {
        self.minutes = minutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// "Weekly Limit", "5-Hour Limit".
    public var title: String {
        minutes == 10080 ? "Weekly Limit" : minutes % 1440 == 0 ? "\(minutes / 1440)-Day Limit" : "\(max(1, minutes / 60))-Hour Limit"
    }
}

/// One agent's usage from its local logs.
public struct AgentUsage: Equatable, Sendable {
    public var today = Spend()
    /// Today and the six days before.
    public var week = Spend()
    /// Today's models, as ccusage names them.
    public var models: [String] = []
    public var block: UsageBlock?
    public var limits: [UsageLimit] = []
    public var plan: String?
    public var credits: String?

    public init() {}
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

/// The active block from `ccusage claude blocks --active --json`, nil when no block is running.
public func activeBlock(_ data: Data) -> UsageBlock? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let block = (json["blocks"] as? [[String: Any]])?.first(where: { $0["isActive"] as? Bool == true }),
          let start = (block["startTime"] as? String).flatMap(isoDate), let end = (block["endTime"] as? String).flatMap(isoDate)
    else { return nil }
    let projection = block["projection"] as? [String: Any]
    return UsageBlock(start: start, end: end, spend: Spend(cost: block["costUSD"] as? Double ?? 0, tokens: block["totalTokens"] as? Int ?? 0),
                      projectedCost: projection?["totalCost"] as? Double)
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
        return UsageLimit(minutes: minutes, usedPercent: reset < now ? 0 : window["used_percent"] as? Double ?? 0, resetsAt: reset)
    }
    let credits = (limits["credits"] as? [String: Any]).flatMap { credits -> String? in
        if credits["unlimited"] as? Bool == true { return "Unlimited" }
        guard credits["has_credits"] as? Bool == true else { return nil }
        return credits["balance"] as? String
    }
    return ((limits["plan_type"] as? String)?.capitalized, windows.sorted { $0.minutes < $1.minutes }, credits)
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
