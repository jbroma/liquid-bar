import AppKit
import SwiftUI

/// The first-launch window: a welcome that asks for Accessibility access, then what is easy to miss on the bar, once.
/// It also follows the grant, which macOS gives no notification for.
@Observable
final class AccessWindow {
    /// The defaults key set once the window has been on screen.
    static let welcomed = "welcomed"

    private(set) var granted = AXIsProcessTrusted()
    /// The request is out; the welcome page shows a waiting state until the grant arrives.
    private(set) var waiting = false
    /// The tips the user has done on the bar while the window is up.
    private(set) var tried: Set<Tip> = []
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var poll: Timer?
    /// Runs once when the grant arrives, to restart what needed it.
    @ObservationIgnored private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) { self.onGranted = onGranted }

    /// Adds the app to the Accessibility list and shows macOS's prompt, whose button opens the list. Opening the list
    /// as well would race the prompt, so the list opens here only when macOS shows no prompt, as after a Deny.
    static func requestAccess() {
        UserDefaults.standard.set(true, forKey: Permission.askedAccessibility)
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let shown = windows.contains { $0[kCGWindowOwnerName as String] as? String == "universalAccessAuthWarn" }
            if !shown { shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'") }
        }
    }

    /// Asks through macOS's prompt, from this window, the Settings window, or a bar item that needs access, and
    /// follows the grant. The window stays a normal one, so System Settings and the prompt open above it.
    func request() {
        Self.requestAccess()
        watch()
        waiting = !granted
    }

    /// The bar reports what the user did, which ticks off the matching tip.
    func did(_ tip: Tip) {
        if window?.isVisible == true { tried.insert(tip) }
    }

    /// Opens Settings on the pane a tip is about. Both windows open mid-screen, so they move side by side when the
    /// screen has the room, and Settings does not cover the tip.
    func showSettings(_ section: SettingsSection) {
        delegate.settings.show(section)
        guard let window, let settings = delegate.settings.window, let screen = window.screen?.visibleFrame,
              window.frame.intersects(settings.frame) else { return }
        let gap: CGFloat = 12
        guard window.frame.width + settings.frame.width + 3 * gap <= screen.width else { return }
        let left = screen.midX - (window.frame.width + gap + settings.frame.width) / 2
        // Settings goes back to where the user keeps it the next time it opens.
        settings.setFrameAutosaveName("")
        window.setFrame(window.frame.offsetBy(dx: left - window.frame.minX, dy: 0), display: true, animate: true)
        settings.setFrame(settings.frame.offsetBy(dx: left + window.frame.width + gap - settings.frame.minX, dy: 0), display: true, animate: true)
    }

    /// Opens the window on its first page.
    func show() {
        watch()
        waiting = false
        tried = []
        window?.close()
        let view = TipsView(state: self, close: { [weak self] in self?.window?.close() })
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(width: 480)
        let content = NSHostingController(rootView: view)
        let window = AppWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        // Centring needs the final size, which the hosting controller only reports after layout.
        window.setContentSize(content.view.fittingSize)
        window.title = ""
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = systemAppearance()
        self.window = window
        bringForward(window)
    }

    /// Polls until the grant arrives, with or without the window, so a grant made later still restarts what needed it.
    func watch() {
        granted = AXIsProcessTrusted()
        poll?.invalidate()
        guard !granted else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard !granted, AXIsProcessTrusted() else { return }
        granted = true
        waiting = false
        poll?.invalidate()
        onGranted()
    }
}
