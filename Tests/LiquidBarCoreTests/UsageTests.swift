import Foundation
import LiquidBarCore
import Testing

@Test func dailySpendReadsClaudeAndCodexReports() throws {
    // Trimmed from `ccusage claude daily --json` and `ccusage codex daily --json` on this Mac.
    let claude = Data(#"""
        {"daily": [{"date": "2026-10-03", "totalCost": 35.02, "totalTokens": 68906367, "modelsUsed": ["claude-sonnet-5-5"]},
                   {"date": "2026-10-04", "totalCost": 7.63, "totalTokens": 20666293, "modelsUsed": ["claude-opus-5-5", "claude-sonnet-5-5"]}],
         "totals": {"totalCost": 728.81, "totalTokens": 1978411617}}
        """#.utf8)
    let read = try #require(dailySpend(claude, today: "2026-10-04"))
    #expect(read.today == Spend(cost: 7.63, tokens: 20666293))
    #expect(read.week == Spend(cost: 728.81, tokens: 1978411617))
    #expect(read.models == ["claude-opus-5-5", "claude-sonnet-5-5"])

    let codex = Data(#"""
        {"daily": [{"date": "2026-10-01", "costUSD": 2.31, "totalTokens": 945136, "models": {"gpt-6-astra": {}}}],
         "totals": {"costUSD": 12.11, "totalTokens": 6632655}}
        """#.utf8)
    let quiet = try #require(dailySpend(codex, today: "2026-10-04"))
    #expect(quiet.today == Spend())
    #expect(quiet.week == Spend(cost: 12.11, tokens: 6632655))
    #expect(quiet.models.isEmpty)
    #expect(try #require(dailySpend(codex, today: "2026-10-01")).models == ["gpt-6-astra"])
    #expect(dailySpend(Data("npm error".utf8), today: "2026-10-04") == nil)
}

@Test func activeBlockReadsTheRunningBlock() throws {
    let data = Data(#"""
        {"blocks": [{"isActive": true, "startTime": "2026-10-04T10:00:00.000Z", "endTime": "2026-10-04T15:00:00.000Z",
                     "costUSD": 8.21, "totalTokens": 20666293, "projection": {"totalCost": 54.03}}]}
        """#.utf8)
    let block = try #require(activeBlock(data))
    #expect(block.start == Date(timeIntervalSince1970: 1_791_108_000))
    #expect(block.end.timeIntervalSince(block.start) == 5 * 3600)
    #expect(block.spend == Spend(cost: 8.21, tokens: 20666293))
    #expect(block.projectedCost == 54.03)
    #expect(activeBlock(Data(#"{"blocks": []}"#.utf8)) == nil)
}

@Test func codexLimitsReadTheSessionLog() throws {
    // A token_count event from a Codex rollout file, trimmed.
    let line = Data(#"""
        {"type": "event_msg", "payload": {"type": "token_count", "rate_limits": {
          "primary": {"used_percent": 12.0, "window_minutes": 10080, "resets_at": 1791196365},
          "secondary": {"used_percent": 40.0, "window_minutes": 300, "resets_at": 1791000000},
          "credits": {"has_credits": true, "unlimited": false, "balance": "62500"}, "plan_type": "pro"}}}
        """#.utf8)
    let read = try #require(codexLimits(line, now: Date(timeIntervalSince1970: 1_791_100_000)))
    #expect(read.plan == "Pro")
    #expect(read.credits == "62500")
    // The 5-hour window reset before now, so it counts as unused; shorter windows come first.
    #expect(read.limits == [
        UsageLimit(minutes: 300, usedPercent: 0, resetsAt: Date(timeIntervalSince1970: 1_791_000_000)),
        UsageLimit(minutes: 10080, usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_791_196_365)),
    ])
    #expect(read.limits.map(\.title) == ["5-Hour Limit", "Weekly Limit"])
    #expect(codexLimits(Data(#"{"payload": {"type": "user_message"}}"#.utf8), now: Date()) == nil)
}

@Test func usageText() {
    #expect(modelTitle("claude-opus-5-5") == "Opus 5.5")
    #expect(modelTitle("claude-sonnet-5") == "Sonnet 5")
    #expect(modelTitle("claude-haiku-4-5-20251001") == "Haiku 4.5")
    #expect(modelTitle("gpt-6-astra") == "gpt-6-astra")
    #expect(costText(8.211) == "$8.21")
    #expect(costText(191.61) == "$192")
    #expect(tokenText(945_136) == "945K")
    #expect(tokenText(20_666_293) == "20.7M")
    #expect(tokenText(1_978_411_617) == "1.98B")
    #expect(tokenText(512) == "512")
}
