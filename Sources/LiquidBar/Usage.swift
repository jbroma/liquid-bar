import AppKit
import LiquidBarCore
import SwiftUI

/// Reads Claude's and Codex's subscription limits while the usage pill is on the bar: at launch, every five minutes,
/// and when its dropdown opens. Claude's come from its usage endpoint, with the login Claude Code keeps in the
/// keychain, which `security` reads without a prompt since Claude Code stored it through `security` too. Codex's come
/// from its newest session log.
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
            async let claude = Self.claude()
            async let codex = blocking { Self.codex() }
            let read = await [UsageAgent.claude: claude, .codex: codex].compactMapValues { $0 }
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

    /// Nil while Claude Code is not signed in. Its limits are empty when the request fails, or once its token has
    /// expired; Claude Code renews it on its next run.
    private static func claude() async -> AgentUsage? {
        guard let login = await run(["/usr/bin/security", "find-generic-password", "-s", "Claude Code-credentials", "-w"])
            .flatMap({ ClaudeLogin(Data($0.utf8)) }) else { return nil }
        return AgentUsage(plan: login.plan, limits: await claudeLimits(login) ?? [])
    }

    private static func claudeLimits(_ login: ClaudeLogin) async -> [UsageLimit]? {
        guard login.expires > Date() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return LiquidBarCore.claudeLimits(data)
    }

    /// The plan and limits in the last line that records them, in the newest of Codex's session logs that has one. They
    /// live under `~/.codex/sessions/<year>/<month>/<day>/`.
    private nonisolated static func codex() -> AgentUsage? {
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
            if let read = lines.compactMap({ codexUsage(Data($0.utf8), now: Date()) }).first { return read }
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
    /// The share of the limit's window gone by, drawn as a brighter stretch of the track.
    var elapsed: Double = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: line)
            Circle()
                .trim(from: 0, to: elapsed)
                .stroke(.white.opacity(0.32), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .rotationEffect(.degrees(-90))
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

/// Each agent's section: its name with a link to its account's usage page, its plan, and its limits as rings. The
/// footer says how fresh it is.
struct UsageMenu: View {
    let model: BarModel

    var body: some View {
        MenuBody {
            let agents = UsageAgent.allCases.filter { model.usage[$0] != nil }
            if agents.isEmpty {
                MenuTitle(title: "Usage")
                MenuRow { Text(model.usageRead == nil ? "Reading usage…" : "Sign in to Claude Code or Codex to see their limits.").foregroundStyle(secondary) }
            }
            ForEach(Array(agents.enumerated()), id: \.element) { index, agent in
                if index > 0 { MenuSeparator().padding(.vertical, 2) }
                if let usage = model.usage[agent] { AgentSection(agent: agent, usage: usage, now: model.now) }
            }
            if let read = model.usageRead {
                Text("Updated \(read.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentIcon(agent: agent, size: 20)
                Text(agent.title).font(.system(size: 13, weight: .semibold))
                // The account's usage page, which has the limits' fine print.
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(secondary)
                    .frame(width: 18, height: 18)
                    .hoverButton(radius: 9) { shell("open '\(agent.usagePage)'") }
                    .help("Open \(URL(string: agent.usagePage)?.host() ?? agent.title)")
                Spacer(minLength: 8)
                if let plan = usage.plan { Badge(text: plan) }
            }
            if usage.limits.isEmpty {
                Text(agent == .claude ? "Limits show once Claude Code is signed in." : "Limits show after your next Codex turn.")
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(usage.limits, id: \.title) { limit in
                        LimitRing(limit: limit, now: now).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// A limit as a ring filled to its use over a track that is brighter as far as the window's time has gone by, so a
/// fill past the bright track is ahead of pace. The percentage sits inside, the name and reset time below.
private struct LimitRing: View {
    let limit: UsageLimit
    let now: Date
    private let size: CGFloat = 58
    private let line: CGFloat = 6

    var body: some View {
        let used = limit.usedPercent / 100
        let elapsed = limit.elapsed(at: now)
        VStack(spacing: 6) {
            UsageDonut(fraction: used, tint: usageTint(limit.usedPercent), size: size, line: line, elapsed: elapsed) {
                Text("\(Int(limit.usedPercent.rounded()))%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            VStack(spacing: 1) {
                Text(limit.title).font(.system(size: 12, weight: .medium))
                Text(resetText).font(.system(size: 10)).foregroundStyle(secondary).monospacedDigit()
            }
            .lineLimit(1)
        }
        .help("\(Int(limit.usedPercent.rounded()))% used, \(Int((elapsed * 100).rounded()))% of the window gone by")
    }

    /// "Resets 17:10" today, else "Resets Fri 03:00".
    private var resetText: String {
        guard limit.resetsAt > now else { return "Reset" }
        let time = limit.resetsAt.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(limit.resetsAt) ? "Resets \(time)" : "Resets \(limit.resetsAt.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// A small capsule label, like the plan.
private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.12)))
    }
}
