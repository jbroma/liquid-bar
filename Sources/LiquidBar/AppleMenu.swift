import AppKit
import LiquidBarCore
import SwiftUI

/// The essentials of the native Apple menu, which is otherwise unreachable while the bar covers the menu bar. Force
/// Quit and LiquidBar unfold inline, one at a time, and the dropdown opens with both folded.
struct AppleMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot
    @State private var expanded: Fold?

    private enum Fold { case forceQuit, liquidBar }

    var body: some View {
        MenuBody {
            row("About This Mac") { shell("open -a 'About This Mac'") }
            row("System Settings…") { shell("open -a 'System Settings'") }
            fold("Force Quit", .forceQuit)
            if expanded == .forceQuit { forceQuitApps }
            MenuSeparator()
            row("Sleep") { shell("pmset sleepnow") }
            // loginwindow's own confirmation dialogs (kAEShowRestartDialog, kAEShowShutdownDialog, kAELogOut).
            row("Restart…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrrst»'"#) }
            row("Shut Down…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrsdn»'"#) }
            MenuSeparator()
            row("Lock Screen") { lockScreen() }
            row("Log Out \(NSFullUserName())…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtlogo»'"#) }
            MenuSeparator()
            fold("LiquidBar", .liquidBar)
            if expanded == .liquidBar { liquidBar }
        }
        // SwiftUI can keep this view's state from one opening to the next; each opens folded.
        .onChange(of: slot.owner == .apple) { _, open in if !open { expanded = nil } }
    }

    /// A row that closes the dropdown, then acts.
    private func row(_ title: String, checked: Bool = false, close: Bool = true, indent: CGFloat = 0, icon: NSImage? = nil, _ action: @escaping () -> Void) -> some View {
        MenuButton {
            if close { slot.dismiss() }
            action()
        } content: {
            if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            if checked { Image(systemName: "checkmark").fontWeight(.semibold) }
        }
        .padding(.leading, indent)
    }

    private func fold(_ title: String, _ section: Fold) -> some View {
        let open = expanded == section
        return MenuButton { withAnimation(spring) { expanded = open ? nil : section } } content: {
            Text(title)
            Spacer(minLength: 8)
            Disclosure(open: open)
        }
    }

    /// The system Force Quit window can only be opened by synthesizing ⌥⌘⎋, which needs Accessibility access.
    /// Listing apps and force-terminating them needs no permission.
    @ViewBuilder private var forceQuitApps: some View {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        ForEach(apps, id: \.processIdentifier) { app in
            row(app.localizedName ?? app.bundleIdentifier ?? "?", indent: 14, icon: app.icon) { app.forceTerminate() }
        }
    }

    /// Every setting edits the config file, which the bar reloads like any other edit. Settings leave the dropdown
    /// open, so the change shows on the bar and in the checkmarks.
    @ViewBuilder private var liquidBar: some View {
        let config = model.config
        let nowPlaying = config.right.contains(.nowPlaying)
        row("About LiquidBar", indent: 14) { delegate.about.show() }
        MenuSeparator().padding(.leading, 14)
        MenuSection(title: "Workspaces").padding(.leading, 14)
        ForEach([("Automatic", WorkspaceSource.auto), ("AeroSpace", .aerospace), ("Desktops", .spaces), ("Apps", .apps)], id: \.0) { title, source in
            setting(title, config.workspaceSource == source, .workspaceSource(source))
        }
        MenuSeparator().padding(.leading, 14)
        MenuSection(title: "Clock").padding(.leading, 14)
        setting("24-Hour", config.clock24Hour, .clock24Hour(true))
        setting("12-Hour", !config.clock24Hour, .clock24Hour(false))
        setting("Show Seconds", config.clockSeconds, .clockSeconds(!config.clockSeconds))
        MenuSeparator().padding(.leading, 14)
        setting("Show Now Playing", nowPlaying, .nowPlaying(!nowPlaying))
        setting("Show Battery Percentage", config.batteryPercent, .batteryPercent(!config.batteryPercent))
        MenuSeparator().padding(.leading, 14)
        row("Open Config File…", indent: 14) {
            do {
                try createConfigFile(at: configURL)
                NSWorkspace.shared.open(configURL)
            } catch {
                log.error("cannot create \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        row("Reload Config", indent: 14) { delegate.configWatcher?.reload() }
        row("Permissions…", indent: 14) { delegate.access.show() }
        MenuSeparator().padding(.leading, 14)
        row("Quit LiquidBar", indent: 14) { delegate.quit() }
    }

    private func setting(_ title: String, _ checked: Bool, _ setting: Setting) -> some View {
        row(title, checked: checked, close: false, indent: 14) { setting.save() }
    }

    private func lockScreen() {
        // The same private call the native "Lock Screen" item uses; there is no public API.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }
}

extension Setting {
    /// Edits the config file, which the bar reloads like any other edit.
    func save() {
        do {
            let data = try applied(to: try? Data(contentsOf: configURL))
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
        } catch {
            log.error("cannot change \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
