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
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // Sparkle's recommendation for an app without a Dock icon: while an update window is up, the app is a regular
    // app, so the window comes forward and Command-Tab reaches it, and a scheduled update badges the Dock icon
    // instead of taking focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        if state.userInitiated {
            NSApp.activate()
        } else {
            NSApp.dockTile.badgeLabel = "1"
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = ""
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
}
