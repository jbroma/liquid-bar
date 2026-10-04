import Foundation
import LiquidBarCore
import Testing

@Test func claudeLimitsReadTheUsageEndpoint() throws {
    // `api/oauth/usage` on this Mac, trimmed; unknown windows and nulls are left out.
    let data = Data(#"""
        {"five_hour": {"utilization": 3.0, "resets_at": "2026-10-04T15:10:00.041798+00:00"},
         "seven_day": {"utilization": 11.0, "resets_at": "2026-10-09T01:00:00.041816+00:00"},
         "seven_day_opus": null, "iguana_necktie": {"utilization": 0.0, "resets_at": "2026-11-05T07:59:00+00:00"}}
        """#.utf8)
    let limits = try #require(claudeLimits(data))
    #expect(limits.map(\.title) == ["Session", "Weekly"])
    #expect(limits.map(\.usedPercent) == [3, 11])
    #expect(limits.map(\.window) == [5 * 3600, 7 * 86400])
    // 15:10 resets the session, so at 12:40 half of its five hours have gone by.
    #expect(limits[0].elapsed(at: Date(timeIntervalSince1970: 1_791_126_600 - 9000)) > 0.49)
    #expect(limits[0].resetsAt.timeIntervalSince1970.rounded() == 1_791_126_600)
    #expect(claudeLimits(Data(#"{"error": {"type": "authentication_error"}}"#.utf8)) == nil)
}

@Test func claudeLoginFromTheKeychainItem() throws {
    let item = Data(#"{"claudeAiOauth": {"accessToken": "t", "expiresAt": 1791137725526, "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x"}}"#.utf8)
    let login = try #require(ClaudeLogin(item))
    #expect(login.token == "t")
    #expect(login.plan == "Max 20x")
    #expect(login.expires == Date(timeIntervalSince1970: 1_791_137_725.526))
    #expect(ClaudeLogin(Data(#"{"claudeAiOauth": {"accessToken": "t", "subscriptionType": "pro"}}"#.utf8))?.plan == "Pro")
    #expect(ClaudeLogin(Data("{}".utf8)) == nil)
}

@Test func codexLimitsReadTheSessionLog() throws {
    // A token_count event from a Codex rollout file, trimmed.
    let line = Data(#"""
        {"type": "event_msg", "payload": {"type": "token_count", "rate_limits": {
          "primary": {"used_percent": 12.0, "window_minutes": 10080, "resets_at": 1791196365},
          "secondary": {"used_percent": 40.0, "window_minutes": 300, "resets_at": 1791000000},
          "credits": {"has_credits": true, "unlimited": false, "balance": "62500"}, "plan_type": "pro"}}}
        """#.utf8)
    let read = try #require(codexUsage(line, now: Date(timeIntervalSince1970: 1_791_100_000)))
    #expect(read.plan == "Pro")
    // The 5-hour window reset before now, so it counts as unused; shorter windows come first.
    #expect(read.limits == [
        UsageLimit(title: "Session", usedPercent: 0, resetsAt: Date(timeIntervalSince1970: 1_791_000_000), window: 18000),
        UsageLimit(title: "Weekly", usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_791_196_365), window: 604_800),
    ])
    #expect(read.tightest?.title == "Weekly")
    #expect(codexUsage(Data(#"{"payload": {"type": "user_message"}}"#.utf8), now: Date()) == nil)
}
