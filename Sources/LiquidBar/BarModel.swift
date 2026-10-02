import AppKit
import LiquidBarCore
import Observation

struct FrontApp: Equatable {
    var name: String
    var pid: pid_t
}

@Observable
final class BarModel {
    var config = Config()
    var workspaces = WorkspaceState()
    /// False while AeroSpace is not answering; the workspaces shown are then the last ones known. Desktops and apps are
    /// always connected.
    var workspacesConnected = false
    var battery: BatteryState?
    var volume = VolumeState(level: 0, muted: false)
    /// Counts the changes to CoreAudio's device list, like headphones connecting, so the Sound dropdown reads it again.
    var audioDevicesChanges = 0
    /// Mission Control is up, or opening or closing.
    var missionControl = false
    /// The strip of desktop picture under each screen's bar, by the screen's frame. Empty where it cannot be read.
    var desktopStrips: [String: CGImage] = [:]
    /// The screens whose bar is over a full-screen window, where there is no desktop picture behind it.
    var coveredScreens: Set<String> = []
    var network = NetworkState(kind: .offline)
    var now = Date()
    /// macOS shows its camera, microphone or screen recording dot at the right end of the menu bar.
    var privacyDot = false
    var scriptLabels: [String: String] = [:]
    var nowPlaying: NowPlaying?
    var artwork: NSImage?
    var frontApp: FrontApp?
    /// Other apps' status items, listed in Control Center's dropdown.
    var menuExtras: [MenuExtra<AXUIElement>] = []
    /// The pinned apps' status items that exist now, in the order pinned.
    var pinnedExtras: [MenuExtra<AXUIElement>] { pinnedItems(menuExtras, pinned: config.pinned) }
    let controls = Controls()

    func focus(_ workspace: String) {
        switch workspaces.source {
        case .spaces:
            guard let n = Int(workspace) else { return }
            guard let shortcut = Desktops.shortcut(n) else { return AppMenus.explainDesktopShortcut(n, at: NSEvent.mouseLocation) }
            guard CGPreflightPostEventAccess() else { return AppMenus.explainAccess("switch desktops", at: NSEvent.mouseLocation) }
            Desktops.press(shortcut)
        case .apps:
            activate(workspace)
        case .aerospace, .auto:
            Task { _ = await run(["aerospace", "workspace", workspace]) }
        }
        haptic()
        workspaces.focused = workspace
    }

    /// `aerospace focus` switches to the window's workspace by itself. Desktops and apps bring the window's app forward.
    func focus(window: Int, on workspace: String) {
        guard workspaces.source == .aerospace else {
            if workspace != workspaces.focused { focus(workspace) }
            return activate(workspaces.windows.first { $0.id == window }?.bundleID)
        }
        haptic()
        workspaces.focused = workspace
        Task { _ = await run(["aerospace", "focus", "--window-id", String(window)]) }
    }

    /// Opening a running app brings it forward, as clicking it in the Dock does.
    private func activate(_ bundleID: String?) {
        guard let url = bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:)) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func scrollWorkspaces(_ steps: Int) {
        if let target = workspaces.neighbor(steps, in: workspaces.ids), target != workspaces.focused {
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
        nowPlaying?.player.permission.tell(command)
    }

    func click(_ widget: Widget) {
        let command = if case .script(let script) = widget { script.click } else { config.clicks[widget.name] }
        guard let command else { return }
        haptic()
        shell(command)
    }
}
