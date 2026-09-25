import Foundation

/// What the notch island is about. Agents win over music; with neither, the island is the bare notch.
public enum IslandContent: Equatable, Sendable {
    case idle
    case agents(AgentSummary)
    case nowPlaying(NowPlaying)

    public init(agents: [AgentThread], nowPlaying: NowPlaying?) {
        let active = agents.filter(\.isActive)
        if let lead = active.min(by: { ($0.status.urgency, $1.updatedAt) < ($1.status.urgency, $0.updatedAt) }) {
            self = .agents(AgentSummary(lead: lead, count: active.count))
        } else if let nowPlaying {
            self = .nowPlaying(nowPlaying)
        } else {
            self = .idle
        }
    }
}

/// The ears: the most urgent active thread (most recent among equals) and how many are active.
public struct AgentSummary: Equatable, Sendable {
    public var lead: AgentThread
    public var count: Int

    public init(lead: AgentThread, count: Int) {
        self.lead = lead
        self.count = count
    }
}

extension AgentStatus {
    /// Lower is more urgent: waiting on the user, then failed, then working.
    var urgency: Int {
        switch self {
        case .needsInput: 0
        case .error: 1
        case .running: 2
        case .done: 3
        case .idle: 4
        }
    }
}

/// Something worth a moment of the island's attention.
public enum IslandPulse: Equatable, Sendable {
    /// A thread that finished (status `.done`) or started waiting on the user.
    case agent(AgentThread)
    case track(NowPlaying)
}

public enum IslandPresentation: Equatable, Sendable {
    case ears
    case pulse(IslandPulse)
    case expanded
}

/// Hover and pulses in, presentation out. Hovering expands the island after a short intent delay and wins over a
/// pulse; leaving keeps it open for a moment so the pointer can cross from the ears into the panel below.
public struct IslandPresenter: Equatable, Sendable {
    public static let hoverIntent: TimeInterval = 0.12
    public static let linger: TimeInterval = 0.35
    public static let pulseLength: TimeInterval = 3

    public private(set) var hoveredSince: Date?
    public private(set) var leftAt: Date?
    public private(set) var pulse: IslandPulse?
    public private(set) var pulseEnd: Date?

    public init() {}

    public mutating func hover(_ inside: Bool, at now: Date) {
        if inside {
            if hoveredSince == nil { hoveredSince = now }
        } else if hoveredSince != nil {
            hoveredSince = nil
            leftAt = now
        }
    }

    /// Closes the panel after a pick. It opens again only once the pointer leaves and comes back.
    public mutating func dismiss() {
        hoveredSince = nil
        leftAt = nil
        pulseEnd = nil
    }

    public mutating func pulse(_ pulse: IslandPulse, at now: Date) {
        self.pulse = pulse
        pulseEnd = now + Self.pulseLength
    }

    /// The presentation at `now` given the current one, and when it can next change by itself. `canExpand` is false
    /// when the panel would be empty.
    public func presentation(at now: Date, current: IslandPresentation, canExpand: Bool) -> (IslandPresentation, recheck: Date?) {
        let wasExpanded = current == .expanded
        let intentEnd = hoveredSince.map { $0 + Self.hoverIntent }.flatMap { $0 > now && !wasExpanded ? $0 : nil }
        let lingerEnd = leftAt.map { $0 + Self.linger }.flatMap { $0 > now ? $0 : nil }
        let activePulse = pulseEnd.flatMap { $0 > now ? pulse : nil }
        let presentation: IslandPresentation =
            if canExpand, hoveredSince != nil, intentEnd == nil { .expanded }
            else if canExpand, wasExpanded, lingerEnd != nil { .expanded }
            else if let activePulse { .pulse(activePulse) }
            else { .ears }
        let recheck = [intentEnd, lingerEnd, pulseEnd.flatMap { $0 > now ? $0 : nil }].compactMap { $0 }.min()
        return (presentation, recheck)
    }
}

/// The drop-down list: active threads first, then the rest updated in the last 12 hours, at most six.
public func islandThreads(_ threads: [AgentThread], now: Date) -> [AgentThread] {
    let recent = threads.filter { $0.isActive || now.timeIntervalSince($0.updatedAt) < 12 * 3600 }
    let (active, rest) = (recent.filter(\.isActive), recent.filter { !$0.isActive })
    return Array((active.sorted { ($0.status.urgency, $1.updatedAt) < ($1.status.urgency, $0.updatedAt) } + rest).prefix(6))
}

/// "12s", "3m", "2h", "4d": how long a thread has been at it, or since it last changed.
public func elapsedText(since start: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}
