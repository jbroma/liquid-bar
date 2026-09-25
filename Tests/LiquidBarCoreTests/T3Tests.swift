import Foundation
import LiquidBarCore
import SQLite3
import Testing

/// A throwaway database with the columns of T3 Code's read model that the bar reads, plus a few it does not.
private func fixture(_ sql: String, schema: String = t3Schema) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "t3-\(UUID().uuidString).sqlite")
    var db: OpaquePointer?
    try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var error: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(db, "PRAGMA journal_mode=WAL;" + schema + sql, nil, nil, &error)
    try #require(status == SQLITE_OK, "\(error.map { String(cString: $0) } ?? "")")
    return url
}

private let t3Schema = """
    CREATE TABLE projection_projects (project_id TEXT PRIMARY KEY, title TEXT NOT NULL, workspace_root TEXT NOT NULL, deleted_at TEXT);
    CREATE TABLE projection_threads (
      thread_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL, latest_turn_id TEXT,
      updated_at TEXT NOT NULL, deleted_at TEXT, archived_at TEXT,
      pending_approval_count INTEGER NOT NULL DEFAULT 0, pending_user_input_count INTEGER NOT NULL DEFAULT 0,
      has_actionable_proposed_plan INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE projection_thread_sessions (
      thread_id TEXT PRIMARY KEY, status TEXT NOT NULL, provider_name TEXT, active_turn_id TEXT, last_error TEXT, updated_at TEXT NOT NULL);
    CREATE TABLE projection_turns (
      row_id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT NOT NULL, turn_id TEXT, state TEXT NOT NULL,
      requested_at TEXT NOT NULL, started_at TEXT, completed_at TEXT);
    INSERT INTO projection_projects VALUES ('p1', 'liquid-bar', '/src/liquid-bar', NULL), ('p2', 'fast-flow', '/src/ff', NULL);
    """

private let threads = """
    INSERT INTO projection_threads (thread_id, project_id, title, latest_turn_id, updated_at, archived_at, deleted_at,
      pending_approval_count, pending_user_input_count, has_actionable_proposed_plan) VALUES
      ('run', 'p1', 'Build the island', 'u1', '2026-09-25T19:10:00.000Z', NULL, NULL, 0, 0, 0),
      ('approve', 'p1', 'Delete old files', 'u2', '2026-09-25T19:12:00.500Z', NULL, NULL, 1, 0, 0),
      ('ask', 'p2', 'Which colour?', 'u3', '2026-09-25T19:11:00Z', NULL, NULL, 0, 2, 0),
      ('plan', 'p2', 'Plan the migration', NULL, '2026-09-25T19:09:00.000Z', NULL, NULL, 0, 0, 1),
      ('fail', 'p2', 'Flaky test', 'u5', '2026-09-25T19:08:00.000Z', NULL, NULL, 0, 0, 0),
      ('quiet', 'p1', 'What is this project', 'u6', '2026-09-24T19:13:23.746Z', NULL, NULL, 0, 0, 0),
      ('nosession', 'p1', 'Fresh thread', NULL, '2026-09-25T18:00:00.000Z', NULL, NULL, 0, 0, 0),
      ('archived', 'p1', 'Old', NULL, '2026-09-25T19:20:00.000Z', '2026-09-25T19:21:00.000Z', NULL, 0, 0, 0),
      ('deleted', 'p1', 'Gone', NULL, '2026-09-25T19:20:00.000Z', NULL, '2026-09-25T19:21:00.000Z', 0, 0, 0);
    INSERT INTO projection_thread_sessions (thread_id, status, provider_name, updated_at) VALUES
      ('run', 'running', 'claudeAgent', 'x'), ('approve', 'running', 'codex', 'x'), ('ask', 'ready', 'codex', 'x'),
      ('plan', 'ready', 'claudeAgent', 'x'), ('fail', 'error', 'codex', 'x'), ('quiet', 'stopped', 'codex', 'x');
    INSERT INTO projection_turns (thread_id, turn_id, state, requested_at, started_at, completed_at) VALUES
      ('run', 'u0', 'completed', '2026-09-25T18:00:00Z', '2026-09-25T18:00:00Z', '2026-09-25T18:01:00Z'),
      ('run', 'u1', 'running', '2026-09-25T19:09:30Z', '2026-09-25T19:09:31.000Z', NULL),
      ('approve', 'u2', 'running', 'x', NULL, NULL),
      ('fail', 'u5', 'error', 'x', NULL, NULL),
      ('quiet', 'u6', 'completed', 'x', NULL, NULL);
    """

@Test func readsThreadsWithT3SidebarPriority() throws {
    let url = try fixture(threads)
    let read = try T3Store.threads(at: url)
    #expect(read.map(\.id) == ["approve", "ask", "run", "plan", "fail", "nosession", "quiet"])
    #expect(read.map(\.status) == [.needsInput, .needsInput, .running, .needsInput, .error, .idle, .idle])
    let run = try #require(read.first { $0.id == "run" })
    #expect(run == AgentThread(
        id: "run", title: "Build the island", project: "liquid-bar", provider: .claude, status: .running,
        updatedAt: Date(timeIntervalSince1970: 1_790_363_400), turn: .running, turnStartedAt: Date(timeIntervalSince1970: 1_790_363_371)))
    #expect(read.first { $0.id == "approve" }?.updatedAt == Date(timeIntervalSince1970: 1_790_363_520.5))
    #expect(read.first { $0.id == "fail" }?.turn == .error)
    #expect(read.first { $0.id == "nosession" }?.provider == .other(""))
    #expect(read.filter(\.isActive).map(\.id) == ["approve", "ask", "run", "plan", "fail"])
}

@Test func readsADatabaseWhoseWriterHasQuit() throws {
    // A writer that closes cleanly checkpoints and removes the WAL side files, which a read-only reader cannot recreate.
    let url = try fixture(threads)
    for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    #expect(try T3Store.threads(at: url).map(\.status) == [.needsInput, .needsInput, .running, .needsInput, .error, .idle, .idle])
    #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
}

@Test func schemaChangeReportsUnavailable() throws {
    let renamed = try fixture("", schema: t3Schema.replacingOccurrences(of: "pending_user_input_count", with: "pending_inputs"))
    #expect(throws: T3Store.Unavailable.self) { try T3Store.threads(at: renamed) }
    let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).sqlite")
    #expect(throws: T3Store.Unavailable.self) { try T3Store.threads(at: missing) }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}

private func thread(_ id: String, _ status: AgentStatus, turn: AgentThread.Turn?) -> AgentThread {
    AgentThread(id: id, title: id, project: "p", provider: .codex, status: status, updatedAt: .distantPast, turn: turn)
}

@Test func finishingATurnAndNewQuestionsAreEvents() {
    let before = [
        thread("a", .running, turn: .running),
        thread("b", .running, turn: .running),
        thread("c", .running, turn: .running),
        thread("d", .idle, turn: .completed),
        thread("e", .needsInput, turn: .running),
    ]
    let after = [
        thread("a", .idle, turn: .completed),
        thread("b", .needsInput, turn: .running),
        thread("c", .idle, turn: .interrupted),
        thread("d", .idle, turn: .completed),
        thread("e", .needsInput, turn: .running),
        thread("new", .needsInput, turn: nil),
    ]
    #expect(agentEvents(before: before, after: after) == [thread("a", .done, turn: .completed), thread("b", .needsInput, turn: .running)])
    #expect(agentEvents(before: after, after: after) == [])
}
