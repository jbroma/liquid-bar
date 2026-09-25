import Foundation
import LiquidBarCore
import Observation

@Observable
final class BarModel {
    var config = Config()
    var workspaces = WorkspaceState()
    var battery: BatteryState?
    var volume = VolumeState(level: 0, muted: false)
    var network = NetworkState.offline
    var now = Date()
    var scriptLabels: [String: String] = [:]

    func focus(_ workspace: String) {
        workspaces.focused = workspace
        Task { _ = await run(["aerospace", "workspace", workspace]) }
    }
}
