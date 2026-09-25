import Foundation

/// One line of `aerospace subscribe` output.
public enum AeroEvent: Equatable, Sendable {
    case focusChanged(workspace: String?)
    case workspaceChanged(String)
    case windowDetected
    case modeChanged(String)
}

public func parseAeroEvent(_ line: String) -> AeroEvent? {
    struct Raw: Decodable {
        let _event: String
        let workspace: String?
        let mode: String?
    }
    guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)) else { return nil }
    switch (raw._event, raw.workspace, raw.mode) {
    case ("focus-changed", let workspace, _): return .focusChanged(workspace: workspace)
    case ("focused-workspace-changed", let workspace?, _): return .workspaceChanged(workspace)
    case ("window-detected", _, _): return .windowDetected
    case ("mode-changed", _, let mode?): return .modeChanged(mode)
    default: return nil
    }
}

/// Parses `aerospace list-windows --all --format '%{workspace}'`: one workspace name per window.
public func parseOccupied(_ output: String) -> Set<String> {
    Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}

extension WorkspaceState {
    /// Applies an event and returns whether window occupancy must be re-read.
    public mutating func apply(_ event: AeroEvent) -> Bool {
        switch event {
        case .focusChanged(let workspace):
            if let workspace { focused = workspace }
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
}
