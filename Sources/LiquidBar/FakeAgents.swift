#if DEBUG
import AppKit
import LiquidBarCore
import SwiftUI

/// Fake agent states for checking the island by eye, and a fake track for the now playing pill: the debug hook's `scene <name>` shows one, and
/// `scene clear` hands the bar back to the real sources.
final class FakeAgents {
    let model: BarModel
    let reloadAgents: () -> Void
    private var saved: (nowPlaying: NowPlaying?, artwork: NSImage?)?

    init(model: BarModel, reloadAgents: @escaping () -> Void) {
        self.model = model
        self.reloadAgents = reloadAgents
    }

    func show(_ scene: String) {
        if scene == "clear" { return end() }
        begin()
        let now = Date()
        switch scene {
        case "running":
            agents([.running, .running, .idle], now)
        case "needsInput":
            agents([.running, .running, .idle], now)
            agents([.running, .needsInput, .idle], now)
        case "done":
            agents([.running, .idle, .idle], now)
            agents([.done, .idle, .idle], now)
        case "error":
            agents([.running, .error, .idle], now)
        case "nowPlaying":
            agents([.idle, .idle, .idle], now)
            let track = saved?.nowPlaying ?? NowPlaying(player: .spotify, title: "Feel Like Summer", artist: "lovelytheband", trackID: "fake", playing: true)
            model.artwork = saved?.artwork ?? Self.artwork
            model.nowPlaying = track
        default:
            FileHandle.standardError.write(Data("liquid-bar: unknown scene \(scene)\n".utf8))
        }
    }

    private func begin() {
        guard !model.faking else { return }
        saved = (model.nowPlaying, model.artwork)
        model.faking = true
        model.nowPlaying = nil
    }

    private func end() {
        guard model.faking else { return }
        model.faking = false
        model.nowPlaying = saved?.nowPlaying
        model.artwork = saved?.artwork
        saved = nil
        reloadAgents()
    }

    /// Three believable threads. `.done` stands for a turn that just completed, reported as T3 would: idle, turn completed.
    private func agents(_ statuses: [AgentStatus], _ now: Date) {
        let base: [(String, String, String, AgentProvider, TimeInterval)] = [
            ("island", "Grow the agent island out of the notch", "liquid-bar", .claude, 74),
            ("passkeys", "Migrate sign-in to passkeys", "t3code", .codex, 252),
            ("flaky", "Fix the flaky checkout test", "storefront", .claude, 2400),
        ]
        let threads = zip(base, statuses).map { entry, status in
            let (id, title, project, provider, age) = entry
            let turn: AgentThread.Turn = status == .done ? .completed : status == .running || status == .needsInput ? .running
                                       : status == .error ? .error : .completed
            return AgentThread(id: id, title: title, project: project, provider: provider, status: status == .done ? .idle : status,
                               updatedAt: now - (status == .idle ? age : 2), turn: turn, turnStartedAt: now - age)
        }
        model.receive(threads, faking: true)
    }

    /// Album art when no real track is playing: a warm sunset gradient.
    private static let artwork: NSImage = {
        let view = ZStack {
            LinearGradient(colors: [Color(hex: 0xFF7A59), Color(hex: 0xFF3D7F), Color(hex: 0x6A3DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0xFFD66B)).frame(width: 90, height: 90).offset(y: 40).blur(radius: 2)
        }
        .frame(width: 256, height: 256)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage ?? NSImage()
    }()
}
#endif
