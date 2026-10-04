import AppKit
import CoreBluetooth
import CoreLocation
import LiquidBarCore

/// What macOS asks the user before a feature works. Apart from Accessibility, which the first launch asks for, each is
/// asked for only when the user first reaches for its feature, and macOS shows one prompt at a time.
enum Permission: CaseIterable, Identifiable {
    case accessibility, bluetooth, location, spotify, music, loginwindow

    enum Status {
        case granted, notAsked, denied
        /// An Automation target that is not running, whose answer macOS gives only while it runs.
        case unknown
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .bluetooth: "Bluetooth"
        case .location: "Location"
        case .spotify: "Spotify"
        case .music: "Music"
        case .loginwindow: "Restart and Shut Down"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "hand.raised.fill"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .location: "location.fill"
        case .spotify, .music, .loginwindow: "gearshape.2.fill"
        }
    }

    var use: String {
        switch self {
        case .accessibility: "App menus, menu bar items, Control Center and Notification Center, Focus, and switching desktops"
        case .bluetooth: "Bluetooth devices in the Sound dropdown and the bar's Control Center"
        case .location: "Wi-Fi network names"
        case .spotify: "Play, pause and skip from the bar"
        case .music: "Play, pause and skip from the bar"
        case .loginwindow: "Restart…, Shut Down… and Log Out… in the Apple dropdown"
        }
    }

    /// The app an Automation permission lets LiquidBar send Apple Events to.
    var app: (name: String, bundleID: String)? {
        switch self {
        case .spotify: (NowPlaying.Player.spotify.appName, NowPlaying.Player.spotify.rawValue)
        case .music: (NowPlaying.Player.music.appName, NowPlaying.Player.music.rawValue)
        case .loginwindow: ("loginwindow", "com.apple.loginwindow")
        case .accessibility, .bluetooth, .location: nil
        }
    }

    /// The permissions worth listing: Automation only for players installed on this Mac.
    static var listed: [Permission] {
        allCases.filter { $0 == .loginwindow || $0.app.map { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil } ?? true }
    }

    /// Read live; macOS posts no notification when a grant changes. Automation asks TCC, which can take a moment, so
    /// `PermissionStatuses` reads it off the main thread.
    var status: Status {
        switch self {
        case .accessibility:
            if AXIsProcessTrusted() { return .granted }
            return UserDefaults.standard.bool(forKey: Self.askedAccessibility) ? .denied : .notAsked
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .location:
            switch LocationAccess.shared.status {
            case .authorizedAlways: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .spotify, .music, .loginwindow:
            return Self.automationStatus(app?.bundleID ?? "")
        }
    }

    nonisolated static func automationStatus(_ bundleID: String) -> Status {
        switch automation(bundleID, ask: false) {
        case noErr: .granted
        case OSStatus(errAEEventWouldRequireUserConsent): .notAsked
        case OSStatus(procNotFound): .unknown
        default: .denied
        }
    }

    var isAutomation: Bool { app != nil }

    /// Accessibility has no "not asked" state of its own; this remembers that LiquidBar asked.
    static let askedAccessibility = "askedAccessibility"

    /// Shows macOS's prompt when it has not asked yet, and otherwise opens the Privacy & Security list where the user
    /// changes the answer.
    func request() {
        if self == .accessibility { return delegate.access.request() }
        guard status == .notAsked else { return openSettings("com.apple.preference.security?\(pane)") }
        switch self {
        case .accessibility:
            break
        case .bluetooth:
            // The first read asks, and waits for the answer.
            Task {
                _ = await Bluetooth.read()
                delegate.model.controls.refresh()
            }
        case .location:
            LocationAccess.shared.request()
        case .spotify, .music, .loginwindow:
            let bundleID = app?.bundleID ?? ""
            Task { _ = await blocking { Self.automation(bundleID, ask: true) } }
        }
    }

    /// Forgets the Accessibility grant macOS holds for LiquidBar, then asks again. A grant made for an earlier build can
    /// still show as on in System Settings while it no longer applies; only removing it lets the new one take.
    static func resetAccessibility() {
        Task {
            _ = await run(["/usr/bin/tccutil", "reset", "Accessibility", Bundle.main.bundleIdentifier ?? "dev.liquidbar"])
            UserDefaults.standard.set(false, forKey: askedAccessibility)
            delegate.access.request()
        }
    }

    /// Sends `command` in AppleScript to the permission's app. After a no, osascript would fail without a word, so
    /// this opens the Automation list instead.
    func tell(_ command: String) {
        guard let app else { return }
        if status == .denied { return request() }
        // The first time, osascript waits on macOS's prompt.
        Task { _ = await run(["osascript", "-e", "tell application \"\(app.name)\" to \(command)"], timeout: 120) }
    }

    private var pane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .bluetooth: "Privacy_Bluetooth"
        case .location: "Privacy_LocationServices"
        case .spotify, .music, .loginwindow: "Privacy_Automation"
        }
    }

    /// Asks TCC about Apple Events to the app; with `ask`, shows the prompt and blocks until the user answers.
    private nonisolated static func automation(_ bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }
}

extension NowPlaying.Player {
    var permission: Permission { self == .spotify ? .spotify : .music }
}

/// Every listed permission's status, read again every second while someone watches, at once when LiquidBar comes back
/// to the front, as it does from System Settings, and a moment after macOS announces an Accessibility change, which it
/// does before the new answer reads back. A grant that arrives while the user is in System Settings brings LiquidBar's
/// Settings back to the front, as the toggle there is the last step.
@Observable
final class PermissionStatuses {
    private(set) var statuses: [Permission: Permission.Status] = [:]

    func refresh() async {
        var next: [Permission: Permission.Status] = [:]
        for permission in Permission.listed {
            if let bundleID = permission.app?.bundleID {
                next[permission] = await blocking { Permission.automationStatus(bundleID) }
            } else {
                next[permission] = permission.status
            }
        }
        guard next != statuses else { return }
        let arrived = !statuses.isEmpty && next.contains { $0.value == .granted && statuses[$0.key] != .granted }
        statuses = next
        if arrived && !NSApp.isActive { delegate.settings.show(.permissions) }
    }

    /// Refreshes until the calling task ends, as a view's `.task` does when the view goes.
    func watch() async {
        let triggers = [
            Task { for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) { await refresh() } },
            Task {
                for await _ in DistributedNotificationCenter.default().notifications(named: .init("com.apple.accessibility.api")) {
                    try? await Task.sleep(for: .milliseconds(250))
                    await refresh()
                }
            },
        ]
        defer { triggers.forEach { $0.cancel() } }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
