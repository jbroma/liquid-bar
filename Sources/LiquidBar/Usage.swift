import AppKit
import LiquidBarCore
import SwiftUI

/// Reads Claude's and Codex's usage while the usage pill is on the bar: at launch, every five minutes, and when its
/// dropdown opens. Claude's limits come from its usage endpoint, with the login Claude Code keeps in the keychain,
/// which `security` reads without a prompt since Claude Code stored it through `security` too. Codex's come from its
/// newest session log. Spend comes from ccusage, run through the login shell so `bunx` or `npx` are on the PATH at
/// login, one run at a time: `bunx` processes started together race over its package cache, and some fail.
final class UsageSource {
    private let model: BarModel
    private var reading = false

    init(model: BarModel) {
        self.model = model
        Task {
            while !Task.isCancelled {
                refresh(ifOlderThan: 0)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh(ifOlderThan age: TimeInterval) {
        guard (model.config.left + model.config.right).contains(.usage), !reading,
              model.usageRead.map({ Date().timeIntervalSince($0) >= age }) ?? true else { return }
        reading = true
        Task {
            var read: [UsageAgent: AgentUsage] = [:]
            for agent in UsageAgent.allCases { read[agent] = await Self.read(agent) }
            reading = false
            // A failed read keeps what was shown and tries again shortly.
            guard !read.isEmpty else {
                try? await Task.sleep(for: .seconds(30))
                return refresh(ifOlderThan: 0)
            }
            if read != model.usage { model.usage = read }
            model.usageRead = Date()
        }
    }

    private static func read(_ agent: UsageAgent) async -> AgentUsage? {
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        let since = day.string(from: Calendar.current.date(byAdding: .day, value: -6, to: Date())!)
        day.dateFormat = "yyyy-MM-dd"
        guard let daily = await ccusage([agent.rawValue, "daily", "--json", "--since", since]),
              let spend = dailySpend(daily, today: day.string(from: Date())) else { return nil }
        var usage = AgentUsage()
        (usage.today, usage.week, usage.models) = spend
        switch agent {
        case .claude:
            if let login = await claudeLogin() {
                usage.plan = login.plan
                usage.limits = await claudeUsage(login) ?? []
            }
        case .codex:
            if let limits = await blocking({ codexSessionLimits() }) { (usage.plan, usage.limits, usage.credits) = limits }
        }
        return usage
    }

    private static func claudeLogin() async -> ClaudeLogin? {
        await run(["/usr/bin/security", "find-generic-password", "-s", "Claude Code-credentials", "-w"]).flatMap { ClaudeLogin(Data($0.utf8)) }
    }

    /// Nil when the request fails, or once Claude Code's token has expired; Claude Code renews it on its next run.
    private static func claudeUsage(_ login: ClaudeLogin) async -> [UsageLimit]? {
        guard login.expires > Date() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return claudeLimits(data)
    }

    private static func ccusage(_ arguments: [String]) async -> Data? {
        let args = arguments.joined(separator: " ")
        let command = "if command -v bunx >/dev/null; then exec bunx ccusage@latest \(args); else exec npx -y ccusage@latest \(args); fi"
        return await run(["/bin/zsh", "-lc", command], timeout: 60).map { Data($0.utf8) }
    }

    /// The limits in the last line that records them, in the newest of Codex's session logs that has one. They live
    /// under `~/.codex/sessions/<year>/<month>/<day>/`.
    private nonisolated static func codexSessionLimits() -> (plan: String?, limits: [UsageLimit], credits: String?)? {
        let files = FileManager.default
        func newest(_ url: URL) -> [URL] {
            ((try? files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        let root = files.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
        let logs = newest(root).lazy.flatMap(newest).flatMap(newest).flatMap { day in
            newest(day).filter { $0.pathExtension == "jsonl" }.sorted {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast
                    > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast
            }
        }
        for log in logs.prefix(10) {
            guard let text = try? String(contentsOf: log, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n").reversed().lazy.filter { $0.contains("\"rate_limits\":{") }
            if let read = lines.compactMap({ codexLimits(Data($0.utf8), now: Date()) }).first { return read }
        }
        return nil
    }
}

/// The pill: each agent's icon in a donut filled to its tightest limit, and that limit's percentage.
struct UsageLabel: View {
    let usage: [UsageAgent: AgentUsage]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(UsageAgent.allCases, id: \.self) { agent in
                let limit = usage[agent]?.tightest
                HStack(spacing: 5) {
                    UsageDonut(fraction: (limit?.usedPercent ?? 0) / 100, tint: limit.map { usageTint($0.usedPercent) } ?? .white) {
                        AgentIcon(agent: agent, size: 11)
                    }
                    if let limit { Text("\(Int(limit.usedPercent.rounded()))%").contentTransition(.numericText()) }
                }
                .help(limit.map { "\(agent.title) \($0.title): \(Int($0.usedPercent.rounded()))%" } ?? agent.title)
            }
        }
        .animation(spring, value: usage)
    }
}

/// A ring filled clockwise from the top to `fraction` over a faint track, with `content` in its middle.
struct UsageDonut<Content: View>: View {
    let fraction: Double
    let tint: Color
    var size: CGFloat = 18
    var line: CGFloat = 2.2
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(fraction, 0.02)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
        .frame(width: size, height: size)
        .animation(spring, value: fraction)
    }
}

/// White while there is room, orange from 70%, red from 90%.
func usageTint(_ percent: Double) -> Color {
    percent >= 90 ? .barRed : percent >= 70 ? Color(hex: 0xff9f0a) : .white
}

private struct AgentIcon: View {
    let agent: UsageAgent
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIcons.icon(agent.bundleID)).resizable().frame(width: size, height: size)
    }
}

/// Each agent's section: its limits as bars, then today's and the week's spend and today's models. The footer says how
/// fresh it is and links each account's usage page, which has the real subscription limits.
struct UsageMenu: View {
    let model: BarModel

    var body: some View {
        MenuBody {
            let agents = UsageAgent.allCases.filter { model.usage[$0] != nil }
            if agents.isEmpty {
                MenuTitle(title: "Usage")
                MenuRow { Text(model.usageRead == nil ? "Reading ccusage…" : "ccusage found no usage, or could not run.").foregroundStyle(secondary) }
            }
            ForEach(Array(agents.enumerated()), id: \.element) { index, agent in
                if index > 0 { MenuSeparator() }
                if let usage = model.usage[agent] { AgentSection(agent: agent, usage: usage, now: model.now) }
            }
            MenuSeparator()
            if let read = model.usageRead {
                MenuRow { Text("Updated \(read.formatted(.relative(presentation: .named))) · spend at API prices").font(.system(size: 11)).foregroundStyle(secondary) }
            }
            ForEach(UsageAgent.allCases, id: \.self) { agent in
                MenuButton { shell("open '\(agent.usagePage)'") } content: { Text("\(agent.title) Usage…") }
            }
        }
        .task { delegate.usage?.refresh(ifOlderThan: 60) }
    }
}

private struct AgentSection: View {
    let agent: UsageAgent
    let usage: AgentUsage
    let now: Date

    var body: some View {
        MenuRow {
            AgentIcon(agent: agent, size: 20)
            Text(agent.title).fontWeight(.semibold)
            Spacer(minLength: 8)
            if let plan = usage.plan { Text(plan).foregroundStyle(secondary) }
        }
        .frame(minHeight: 30)
        if usage.limits.isEmpty {
            MenuRow { Text(agent == .claude ? "Limits show once Claude Code is signed in." : "Limits show after your next Codex turn.").foregroundStyle(secondary) }
        }
        ForEach(usage.limits, id: \.title) { limit in
            UsageMeter(title: limit.title, value: "\(Int(limit.usedPercent.rounded()))%", fraction: limit.usedPercent / 100,
                       tint: usageTint(limit.usedPercent), caption: "Resets \(resetText(limit.resetsAt))")
        }
        // At API prices, which a subscription does not charge; it shows how much the plan covered.
        MenuValue(title: "Today", value: spendText(usage.today))
        MenuValue(title: "Last 7 Days", value: spendText(usage.week))
        if !usage.models.isEmpty { MenuValue(title: "Models", value: usage.models.map(modelTitle).joined(separator: ", ")) }
        if let credits = usage.credits { MenuValue(title: "Credits", value: credits) }
    }

    private func spendText(_ spend: Spend) -> String {
        spend.tokens == 0 ? "None" : "\(costText(spend.cost)) · \(tokenText(spend.tokens))"
    }

    /// "at 17:00" today, else the weekday and time.
    private func resetText(_ date: Date) -> String {
        guard date > now else { return "now" }
        return Calendar.current.isDateInToday(date) ? "at \(date.formatted(date: .omitted, time: .shortened))"
            : date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

/// A title and value over a thin bar filled to `fraction`, and a dimmed caption under it.
private struct UsageMeter: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(value).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(tint).frame(width: max(6, proxy.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
            Text(caption).font(.system(size: 11)).foregroundStyle(secondary).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .animation(spring, value: fraction)
    }
}
