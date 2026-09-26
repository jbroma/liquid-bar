import AppKit
import LiquidBarCore
import Observation

struct FrontApp: Equatable {
    var name: String
    var bundleID: String
    var pid: pid_t
}

@Observable
final class BarModel {
    var config = Config()
    var workspaces = WorkspaceState()
    var battery: BatteryState?
    var volume = VolumeState(level: 0, muted: false)
    var network = NetworkState(kind: .offline)
    var now = Date()
    var scriptLabels: [String: String] = [:]
    var nowPlaying: NowPlaying?
    var artwork: NSImage?
    var frontApp: FrontApp?

    func focus(_ workspace: String) {
        haptic()
        workspaces.focused = workspace
        Task { _ = await run(["aerospace", "workspace", workspace]) }
    }

    func scrollWorkspaces(_ steps: Int) {
        if let target = workspaces.neighbor(steps, in: config.workspaces.map(\.id)), target != workspaces.focused {
            focus(target)
        }
    }

    func nudgeVolume(_ steps: Int) {
        let level = volume.stepped(steps)
        volume = VolumeState(level: level, muted: volume.muted && level == 0, device: volume.device)
        setSystemVolume(level)
    }

    /// "playpause", "next track" or "previous track"; both players understand the same commands.
    func control(_ command: String) {
        guard let player = nowPlaying?.player else { return }
        Task { _ = await run(["osascript", "-e", "tell application \"\(player.appName)\" to \(command)"]) }
    }

    func click(_ widget: Widget) {
        haptic()
        if case .script(let script) = widget {
            if let command = script.click { shell(command) }
        } else if let command = config.clicks[widget.name] {
            shell(command)
        }
    }
}
