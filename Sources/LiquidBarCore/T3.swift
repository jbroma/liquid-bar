import Foundation
import SQLite3

/// Reads T3 Code's own read model, `~/.t3/userdata/state.sqlite`, strictly read-only. T3 Code is alpha and its schema
/// moves; every table and column the bar depends on is in `query`, and a mismatch throws instead of guessing.
public enum T3Store {
    public struct Unavailable: Error, CustomStringConvertible {
        public let description: String
    }

    public static let defaultURL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".t3/userdata/state.sqlite")

    static let query = """
        SELECT t.thread_id, t.title, p.title, s.provider_name, s.status,
               t.pending_approval_count, t.pending_user_input_count, t.has_actionable_proposed_plan,
               t.updated_at, turn.state, turn.started_at
        FROM projection_threads t
        JOIN projection_projects p ON p.project_id = t.project_id
        LEFT JOIN projection_thread_sessions s ON s.thread_id = t.thread_id
        LEFT JOIN projection_turns turn ON turn.thread_id = t.thread_id AND turn.turn_id = t.latest_turn_id
        WHERE t.deleted_at IS NULL AND t.archived_at IS NULL
        ORDER BY t.updated_at DESC
        LIMIT 30
        """

    /// Non-archived threads, most recently updated first.
    public static func threads(at url: URL = defaultURL) throws -> [AgentThread] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        // A read-only connection cannot create the WAL side files. Without a WAL file there is no writer and nothing
        // left to checkpoint, so the database file alone is the whole truth and can be opened as immutable.
        let hasWAL = FileManager.default.fileExists(atPath: url.path + "-wal")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "file"
        components.queryItems = hasWAL ? nil : [URLQueryItem(name: "immutable", value: "1")]
        guard FileManager.default.fileExists(atPath: url.path),
              sqlite3_open_v2(components.string!, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else {
            throw Unavailable(description: "cannot open \(url.path): \(message(db))")
        }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw Unavailable(description: "schema changed: \(message(db))")
        }
        var threads: [AgentThread] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return threads }
            guard step == SQLITE_ROW else { throw Unavailable(description: "read failed: \(message(db))") }
            func text(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
            func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
            let row = Row(
                sessionStatus: text(4), pendingApprovals: int(5), pendingInputs: int(6), proposedPlan: int(7) != 0, turnState: text(9))
            threads.append(AgentThread(
                id: text(0) ?? "",
                title: text(1) ?? "",
                project: text(2) ?? "",
                provider: AgentProvider(text(3)),
                status: row.status,
                updatedAt: text(8).flatMap(parseTimestamp) ?? .distantPast,
                turn: row.turn,
                turnStartedAt: text(10).flatMap(parseTimestamp)
            ))
        }
    }

    /// The status fields of one thread, as T3 stores them.
    struct Row {
        var sessionStatus: String?
        var pendingApprovals: Int
        var pendingInputs: Int
        var proposedPlan: Bool
        var turnState: String?

        /// T3's own sidebar priority: pending approval or question, then a working session, then a failed one.
        var status: AgentStatus {
            if pendingApprovals > 0 || pendingInputs > 0 { return .needsInput }
            if sessionStatus == "running" || sessionStatus == "starting" { return .running }
            if proposedPlan { return .needsInput }
            if sessionStatus == "error" { return .error }
            return .idle
        }

        var turn: AgentThread.Turn? {
            switch turnState {
            case "running": .running
            case "completed": .completed
            case "interrupted": .interrupted
            case "error": .error
            default: nil
            }
        }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
    }
}

/// "2026-09-25T19:13:37.864Z", with or without fractional seconds.
func parseTimestamp(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
