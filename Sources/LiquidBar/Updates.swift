import AppKit
import LiquidBarCore
import Sparkle

/// Sparkle checks `SUFeedURL` once a day and installs an update once the user accepts it. A copy in the Nix store has
/// no updater: Nix replaces it.
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    var updater: SPUUpdater? { controller?.updater }

    override init() {
        super.init()
        guard !updatedByNix(bundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func check() {
        // Sparkle's "Checking for updates" and "You're up to date" windows would open behind the front app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // Sparkle's recommendation for an app without a Dock icon: while an update window is up, the app is a regular
    // app, so the window comes forward and Command-Tab reaches it. A background app's window would otherwise open
    // behind the front app with dimmed buttons, so a scheduled update comes forward too.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        // `activate()` alone is turned down while the app is in the background; see `bringForward`.
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        followWindows()
    }
}
