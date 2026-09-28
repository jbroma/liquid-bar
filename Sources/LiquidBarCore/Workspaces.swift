import Foundation

/// Where the strip's workspaces come from: AeroSpace, the macOS desktops (Spaces), or the running apps.
public enum WorkspaceSource: String, CaseIterable, Sendable {
    case auto, aerospace, spaces, apps

    /// `auto` is AeroSpace while it runs, else the desktops when there are two or more, else the apps.
    public func resolved(aerospaceRunning: Bool, desktops: Int) -> WorkspaceSource {
        guard self == .auto else { return self }
        if aerospaceRunning { return .aerospace }
        return desktops >= 2 ? .spaces : .apps
    }
}

extension WorkspaceState {
    /// Apps show only their icon; workspaces and desktops also show their number.
    public var numbered: Bool { source != .apps }

    public func title(_ id: String) -> String {
        source == .spaces ? "Desktop \(id)" : "Workspace \(id)"
    }
}

/// One display's desktops, the user Spaces of Mission Control.
public struct DisplaySpaces: Equatable, Sendable {
    public var display: String
    /// Space IDs in Mission Control order, without fullscreen Spaces.
    public var desktops: [UInt64]
    public var current: UInt64?

    public init(display: String, desktops: [UInt64], current: UInt64?) {
        self.display = display
        self.desktops = desktops
        self.current = current
    }
}

/// Parses `SLSCopyManagedDisplaySpaces`: per display a "Display Identifier", a "Current Space" and its "Spaces", each
/// with an `id64` and a `type`, 0 for a desktop and 4 for a fullscreen app.
public func parseDisplaySpaces(_ list: [[String: Any]]) -> [DisplaySpaces] {
    func id(_ space: Any?) -> UInt64? { ((space as? [String: Any])?["id64"] as? NSNumber)?.uint64Value }
    return list.compactMap { display in
        guard let name = display["Display Identifier"] as? String, let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
        let desktops = spaces.filter { ($0["type"] as? NSNumber)?.intValue == 0 }.compactMap(id)
        return DisplaySpaces(display: name, desktops: desktops, current: id(display["Current Space"]))
    }
}

extension WorkspaceState {
    /// A display's first nine desktops, numbered from 1. `windows` maps a Space ID to its window IDs front to back,
    /// `owners` a window ID to its app's bundle ID; windows without a known owner are left out.
    public init(desktops: DisplaySpaces, windows: [UInt64: [Int]], owners: [Int: String]) {
        let numbered = desktops.desktops.prefix(9).enumerated().map { (id: String($0.offset + 1), space: $0.element) }
        let current = numbered.first { $0.space == desktops.current }?.id
        let list = numbered.flatMap { desktop in
            (windows[desktop.space] ?? []).compactMap { window in
                owners[window].map { Window(id: window, workspace: desktop.id, bundleID: $0) }
            }
        }
        // Front to back, the current desktop first, so its front window counts as the focused one. A window on all
        // desktops is listed on each but ranked once.
        var seen = Set<Int>()
        let recency = (list.filter { $0.workspace == current } + list).map(\.id).filter { seen.insert($0).inserted }
        self.init(source: .spaces, ids: numbered.map(\.id), focused: current, windows: list, recency: recency)
    }
}

public struct RunningApp: Equatable, Sendable {
    public var pid: Int
    public var bundleID: String

    public init(pid: Int, bundleID: String) {
        self.pid = pid
        self.bundleID = bundleID
    }
}

extension WorkspaceState {
    /// One workspace per app, named by its bundle ID, the most recently activated first. `recency` holds PIDs, the
    /// front app first; apps not in it follow in the order given.
    public init(apps: [RunningApp], recency: [Int]) {
        let rank = Dictionary(recency.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        var seen = Set<String>()
        let ordered = apps.enumerated()
            .sorted { (rank[$0.element.pid] ?? Int.max, $0.offset) < (rank[$1.element.pid] ?? Int.max, $1.offset) }
            .map(\.element)
            .filter { seen.insert($0.bundleID).inserted }
        self.init(
            source: .apps,
            ids: ordered.map(\.bundleID),
            focused: ordered.first { $0.pid == recency.first }?.bundleID,
            windows: ordered.map { Window(id: $0.pid, workspace: $0.bundleID, bundleID: $0.bundleID) },
            recency: recency.filter { pid in ordered.contains { $0.pid == pid } }
        )
    }
}

/// A key combination as `com.apple.symbolichotkeys` stores it: a virtual key code and modifier flags with the same
/// bits as `CGEventFlags`.
public struct KeyShortcut: Equatable, Sendable {
    public var keyCode: Int
    public var modifiers: UInt64

    public init(keyCode: Int, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The "Switch to Desktop `n`" shortcut from `AppleSymbolicHotKeys`, where desktops 1 to 9 are entries 118 to 126, or
/// nil while it is off. macOS ships them off and without an entry.
public func desktopShortcut(_ n: Int, in hotkeys: [String: Any]) -> KeyShortcut? {
    guard let entry = hotkeys[String(117 + n)] as? [String: Any],
          (entry["enabled"] as? NSNumber)?.boolValue == true,
          let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], parameters.count == 3
    else { return nil }
    return KeyShortcut(keyCode: parameters[1].intValue, modifiers: parameters[2].uint64Value)
}
