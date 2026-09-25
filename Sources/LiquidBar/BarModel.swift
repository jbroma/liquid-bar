import Foundation
import LiquidBarCore
import Observation

@Observable
final class BarModel {
    var config = Config()
    var workspaces = WorkspaceState()
    var battery: BatteryState?
    var volume = VolumeState(level: 0, muted: false)
    var network = NetworkState(kind: .offline)
    var now = Date()
    var scriptLabels: [String: String] = [:]

    func focus(_ workspace: String) {
        workspaces.focused = workspace
        Task { _ = await run(["aerospace", "workspace", workspace]) }
    }

    func nudgeVolume(_ steps: Int) {
        let level = volume.stepped(steps)
        volume = VolumeState(level: level, muted: volume.muted && level == 0, device: volume.device)
        setSystemVolume(level)
    }

    func click(_ widget: Widget) {
        if case .script(let script) = widget {
            if let command = script.click { shell(command) }
        } else if let command = config.clicks[widget.name] {
            shell(command)
        }
    }
}
