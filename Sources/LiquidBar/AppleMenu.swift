import AppKit
import LiquidBarCore

/// The essentials of the native Apple menu, which is otherwise unreachable while the bar covers the menu bar.
enum AppleMenu {
    static func popUp(at screenPoint: NSPoint, config: Config) {
        let menu = NSMenu()
        menu.addItem(actionItem("About This Mac") { shell("open -a 'About This Mac'") })
        menu.addItem(actionItem("System Settings…") { shell("open -a 'System Settings'") })
        menu.addItem(liquidBarItem(config))
        menu.addItem(forceQuitItem())
        menu.addItem(.separator())
        menu.addItem(actionItem("Sleep") { shell("pmset sleepnow") })
        // loginwindow's own confirmation dialogs (kAEShowRestartDialog, kAEShowShutdownDialog, kAELogOut).
        menu.addItem(actionItem("Restart…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrrst»'"#) })
        menu.addItem(actionItem("Shut Down…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrsdn»'"#) })
        menu.addItem(.separator())
        menu.addItem(actionItem("Lock Screen") { lockScreen() })
        menu.addItem(actionItem("Log Out \(NSFullUserName())…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtlogo»'"#) })
        menu.popUp(below: screenPoint)
    }

    /// Every setting edits the config file, which the bar reloads like any other edit.
    private static func liquidBarItem(_ config: Config) -> NSMenuItem {
        let sources: [(String, WorkspaceSource)] = [("Automatic", .auto), ("AeroSpace", .aerospace), ("Desktops", .spaces), ("Apps", .apps)]
        let nowPlaying = config.right.contains(.nowPlaying)
        return submenu("LiquidBar", [
            submenu("Workspaces", sources.map { title, source in
                settingItem(title, checked: config.workspaceSource == source, .workspaceSource(source))
            }),
            submenu("Clock", [
                settingItem("24-Hour", checked: config.clock24Hour, .clock24Hour(true)),
                settingItem("12-Hour", checked: !config.clock24Hour, .clock24Hour(false)),
                .separator(),
                settingItem("Show Seconds", checked: config.clockSeconds, .clockSeconds(!config.clockSeconds)),
            ]),
            settingItem("Show Now Playing", checked: nowPlaying, .nowPlaying(!nowPlaying)),
            settingItem("Show Battery Percentage", checked: config.batteryPercent, .batteryPercent(!config.batteryPercent)),
            .separator(),
            actionItem("Open Config File…") {
                do {
                    try createConfigFile(at: configURL)
                    NSWorkspace.shared.open(configURL)
                } catch {
                    log.error("cannot create \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            },
            actionItem("Reload Config") { delegate.configWatcher?.reload() },
            .separator(),
            actionItem("Quit LiquidBar") { delegate.quit() },
        ])
    }

    private static func settingItem(_ title: String, checked: Bool, _ setting: Setting) -> NSMenuItem {
        let item = actionItem(title) {
            do {
                let data = try setting.applied(to: try? Data(contentsOf: configURL))
                try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: configURL, options: .atomic)
            } catch {
                log.error("cannot change \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        item.state = checked ? .on : .off
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        items.forEach(item.submenu!.addItem)
        return item
    }

    /// The system Force Quit window can only be opened by synthesizing ⌥⌘⎋, which needs Accessibility access.
    /// Listing apps and force-terminating them needs no permission.
    private static func forceQuitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Force Quit", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in apps {
            let entry = actionItem(app.localizedName ?? app.bundleIdentifier ?? "?") { app.forceTerminate() }
            entry.image = app.icon.map { icon in
                icon.size = NSSize(width: 16, height: 16)
                return icon
            }
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private static func lockScreen() {
        // The same private call the native "Lock Screen" item uses; there is no public API.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }
}

/// Menu items that run a closure, without a target object per item.
func actionItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(MenuTarget.fire), keyEquivalent: "")
    item.target = MenuTarget.shared
    item.representedObject = handler
    return item
}

final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    @objc func fire(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }
}
