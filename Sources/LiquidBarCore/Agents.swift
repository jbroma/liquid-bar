import Foundation

/// What a coding agent thread is doing, as the island shows it. Provider-neutral: T3 Code feeds it today.
public enum AgentStatus: Equatable, Sendable {
    case running, needsInput, done, error, idle
}

public enum AgentProvider: Equatable, Sendable {
    case codex, claude
    case other(String)

    public init(_ name: String?) {
        switch name {
        case "codex": self = .codex
        case "claudeAgent", "claude", "claudeCode": self = .claude
        default: self = .other(name ?? "")
        }
    }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .other(let name): name.isEmpty ? "Agent" : name
        }
    }
}

public struct AgentThread: Identifiable, Equatable, Sendable {
    public enum Turn: Equatable, Sendable { case running, completed, interrupted, error }

    public var id: String
    public var title: String
    public var project: String
    public var provider: AgentProvider
    public var status: AgentStatus
    public var updatedAt: Date
    /// State and start of the thread's latest turn; drives the finish pulse and the elapsed time.
    public var turn: Turn?
    public var turnStartedAt: Date?

    public init(id: String, title: String, project: String, provider: AgentProvider, status: AgentStatus, updatedAt: Date,
                turn: Turn? = nil, turnStartedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.project = project
        self.provider = provider
        self.status = status
        self.updatedAt = updatedAt
        self.turn = turn
        self.turnStartedAt = turnStartedAt
    }

    /// Running, waiting on the user, or failed: the threads the island's ears show.
    public var isActive: Bool {
        [.running, .needsInput, .error].contains(status)
    }
}

/// Threads that just finished a turn (returned with status `.done`) or just started waiting on the user, between two
/// reads. Finishing is a transition, not a state: a turn seen running that is now completed.
public func agentEvents(before: [AgentThread], after: [AgentThread]) -> [AgentThread] {
    let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return after.compactMap { thread in
        guard let previous = old[thread.id] else { return nil }
        if thread.status == .needsInput, previous.status != .needsInput { return thread }
        if previous.turn == .running, thread.turn == .completed, thread.status == .idle {
            var done = thread
            done.status = .done
            return done
        }
        return nil
    }
}
