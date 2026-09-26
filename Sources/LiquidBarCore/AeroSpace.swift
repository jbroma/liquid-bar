import Foundation

/// One line of `aerospace subscribe` output.
public enum AeroEvent: Equatable, Sendable {
    case focusChanged(workspace: String?, windowID: Int?)
    case workspaceChanged(String)
    case windowDetected
    case modeChanged(String)
}

public func parseAeroEvent(_ line: String) -> AeroEvent? {
    struct Raw: Decodable {
        let _event: String
        let workspace: String?
        let windowId: Int?
        let mode: String?
    }
    guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)) else { return nil }
    switch (raw._event, raw.workspace, raw.mode) {
    case ("focus-changed", let workspace, _): return .focusChanged(workspace: workspace, windowID: raw.windowId)
    case ("focused-workspace-changed", let workspace?, _): return .workspaceChanged(workspace)
    case ("window-detected", _, _): return .windowDetected
    case ("mode-changed", _, let mode?): return .modeChanged(mode)
    default: return nil
    }
}

public struct Window: Equatable, Sendable {
    public var id: Int
    public var workspace: String
    public var bundleID: String

    public init(id: Int, workspace: String, bundleID: String) {
        self.id = id
        self.workspace = workspace
        self.bundleID = bundleID
    }
}

/// Parses `aerospace list-windows --all --format '%{workspace}|%{window-id}|%{app-bundle-id}'`.
public func parseWindows(_ output: String) -> [Window] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 3, !fields[0].isEmpty, let id = Int(fields[1]) else { return nil }
        return Window(id: id, workspace: fields[0], bundleID: fields[2])
    }
}

/// One app on a workspace, as its dropdown lists it.
public struct WorkspaceApp: Equatable, Sendable {
    public var bundleID: String
    /// The app's most recently focused window on the workspace, which a click focuses.
    public var windowID: Int
    /// It holds the focused window.
    public var focused: Bool

    public init(bundleID: String, windowID: Int, focused: Bool) {
        self.bundleID = bundleID
        self.windowID = windowID
        self.focused = focused
    }
}

extension WorkspaceState {
    /// Applies an event and returns whether the window list must be re-read.
    public mutating func apply(_ event: AeroEvent) -> Bool {
        switch event {
        case .focusChanged(let workspace, let windowID):
            if let workspace { focused = workspace }
            if let windowID { recency = [windowID] + recency.filter { $0 != windowID } }
            return true
        case .workspaceChanged(let workspace):
            focused = workspace
            return false
        case .windowDetected:
            return true
        case .modeChanged(let newMode):
            mode = newMode
            return false
        }
    }

    /// Replaces the window list and forgets closed windows. Windows never focused since launch rank last.
    public mutating func setWindows(_ windows: [Window]) {
        self.windows = windows
        let alive = Set(windows.map(\.id))
        recency = recency.filter(alive.contains)
    }

    public var occupied: Set<String> { Set(windows.map(\.workspace)) }

    /// The apps on `workspace`, the app of its most recently focused window first, each with that window.
    public func apps(on workspace: String) -> [WorkspaceApp] {
        let rank = Dictionary(uniqueKeysWithValues: recency.enumerated().map { ($1, $0) })
        var seen = Set<String>()
        return windows.enumerated()
            .filter { $0.element.workspace == workspace }
            .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
            .map(\.element)
            .filter { seen.insert($0.bundleID).inserted }
            .map { WorkspaceApp(bundleID: $0.bundleID, windowID: $0.id, focused: workspace == focused && $0.id == recency.first) }
    }

    /// The workspace `steps` away from the focused one, among those with windows plus the focused one, in
    /// config order and clamped at the ends, like scrolling through AeroSpace's `workspace next`/`prev`.
    public func neighbor(_ steps: Int, in order: [String]) -> String? {
        let candidates = order.filter { occupied.contains($0) || $0 == focused }
        guard let focused, let index = candidates.firstIndex(of: focused) else { return candidates.first }
        return candidates[min(max(index + steps, 0), candidates.count - 1)]
    }
}
