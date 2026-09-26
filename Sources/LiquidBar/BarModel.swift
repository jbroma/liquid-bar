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
        setVolume(volume.stepped(steps))
    }

    func setVolume(_ level: Int) {
        volume = VolumeState(level: level, muted: volume.muted && level == 0, device: volume.device)
        setSystemVolume(level)
    }

    /// "playpause", "next track" or "previous track"; both players understand the same commands.
    func control(_ command: String) {
        guard let player = nowPlaying?.player else { return }
        Task { _ = await run(["osascript", "-e", "tell application \"\(player.appName)\" to \(command)"]) }
    }

    func click(_ widget: Widget) {
        let command = if case .script(let script) = widget { script.click } else { config.clicks[widget.name] }
        guard let command else { return }
        haptic()
        shell(command)
    }
}
