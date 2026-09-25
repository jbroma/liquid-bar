import Foundation
import LiquidBarCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_790_363_400)
private func at(_ seconds: Double) -> Date { t0 + seconds }

private func thread(_ id: String, _ status: AgentStatus, updated: Double = 0) -> AgentThread {
    AgentThread(id: id, title: id, project: "p", provider: .claude, status: status, updatedAt: at(updated))
}

private let song = NowPlaying(player: .spotify, title: "Feel Like Summer", artist: "lovelytheband", trackID: "t", playing: true)

@Test func agentsWinOverMusicAndTheMostUrgentThreadLeads() {
    let threads = [thread("old-run", .running, updated: -60), thread("new-run", .running, updated: -5), thread("quiet", .idle)]
    #expect(IslandContent(agents: threads, nowPlaying: song) == .agents(AgentSummary(lead: threads[1], count: 2)))
    let failed = threads + [thread("fail", .error, updated: -300)]
    #expect(IslandContent(agents: failed, nowPlaying: nil) == .agents(AgentSummary(lead: failed[3], count: 3)))
    let asking = failed + [thread("ask", .needsInput, updated: -900)]
    #expect(IslandContent(agents: asking, nowPlaying: nil) == .agents(AgentSummary(lead: asking[4], count: 4)))
    #expect(IslandContent(agents: [thread("quiet", .idle)], nowPlaying: song) == .nowPlaying(song))
    #expect(IslandContent(agents: [thread("quiet", .idle)], nowPlaying: nil) == .idle)
}

@Test func hoverExpandsAfterIntentAndLingersOnLeave() {
    var presenter = IslandPresenter()
    presenter.hover(true, at: t0)
    #expect(presenter.presentation(at: at(0.05), current: .ears, canExpand: true) == (.ears, at(0.12)))
    #expect(presenter.presentation(at: at(0.2), current: .ears, canExpand: true) == (.expanded, nil))
    #expect(presenter.presentation(at: at(0.2), current: .ears, canExpand: false) == (.ears, nil))
    presenter.hover(false, at: at(1))
    #expect(presenter.presentation(at: at(1.2), current: .expanded, canExpand: true) == (.expanded, at(1.35)))
    #expect(presenter.presentation(at: at(1.4), current: .expanded, canExpand: true) == (.ears, nil))
    // Crossing from the ears into the panel re-enters within the linger and stays open without waiting for intent.
    presenter.hover(true, at: at(1.3))
    #expect(presenter.presentation(at: at(1.31), current: .expanded, canExpand: true) == (.expanded, at(1.35)))
}

@Test func pickingAThreadClosesThePanel() {
    var presenter = IslandPresenter()
    presenter.hover(true, at: t0)
    presenter.pulse(.agent(thread("a", .done)), at: t0)
    presenter.dismiss()
    #expect(presenter.presentation(at: at(1), current: .expanded, canExpand: true) == (.ears, nil))
    presenter.hover(true, at: at(2))
    #expect(presenter.presentation(at: at(2.2), current: .ears, canExpand: true) == (.expanded, nil))
}

@Test func pulseShowsForThreeSecondsUnlessHovered() {
    var presenter = IslandPresenter()
    let done = IslandPulse.agent(thread("a", .done))
    presenter.pulse(done, at: t0)
    #expect(presenter.presentation(at: at(1), current: .ears, canExpand: true) == (.pulse(done), at(3)))
    #expect(presenter.presentation(at: at(3), current: .pulse(done), canExpand: true) == (.ears, nil))
    presenter.pulse(.track(song), at: at(10))
    presenter.hover(true, at: at(10.5))
    #expect(presenter.presentation(at: at(11), current: .pulse(.track(song)), canExpand: true) == (.expanded, at(13)))
}

@Test func dropDownListsActiveThreadsFirstThenRecentOnes() {
    let threads = [
        thread("recent", .idle, updated: -3600),
        thread("run", .running, updated: -10),
        thread("stale", .idle, updated: -13 * 3600),
        thread("stale-ask", .needsInput, updated: -20 * 3600),
        thread("older", .idle, updated: -7200),
    ]
    #expect(islandThreads(threads, now: t0).map(\.id) == ["stale-ask", "run", "recent", "older"])
    let many = (0..<9).map { thread("t\($0)", .idle, updated: Double(-$0)) }
    #expect(islandThreads(many, now: t0).map(\.id) == ["t0", "t1", "t2", "t3", "t4", "t5"])
}

@Test func elapsedTimeReadsAtAGlance() {
    #expect(elapsedText(since: t0, now: at(12)) == "12s")
    #expect(elapsedText(since: t0, now: at(185)) == "3m")
    #expect(elapsedText(since: t0, now: at(2 * 3600 + 59)) == "2h")
    #expect(elapsedText(since: t0, now: at(4 * 86400)) == "4d")
    #expect(elapsedText(since: at(5), now: t0) == "0s")
}
