import AppKit
import SwiftUI

/// The essentials of the native Apple menu, which is otherwise unreachable while the bar covers the menu bar. Force
/// Quit unfolds inline, and the dropdown opens with it folded.
struct AppleMenu: View {
    @Environment(ExpansionSlot.self) private var slot
    @State private var forceQuit = false

    var body: some View {
        MenuBody {
            row("About This Mac") { shell("open -a 'About This Mac'") }
            row("System Settings…") { shell("open -a 'System Settings'") }
            MenuButton { withAnimation(spring) { forceQuit.toggle() } } content: {
                Text("Force Quit")
                Spacer(minLength: 8)
                Disclosure(open: forceQuit)
            }
            if forceQuit { forceQuitApps }
            MenuSeparator()
            row("Sleep") { shell("pmset sleepnow") }
            // loginwindow's own confirmation dialogs (kAEShowRestartDialog, kAEShowShutdownDialog, kAELogOut).
            row("Restart…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrrst»'"#) }
            row("Shut Down…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtrsdn»'"#) }
            MenuSeparator()
            row("Lock Screen") { lockScreen() }
            row("Log Out \(NSFullUserName())…") { shell(#"osascript -e 'tell application "loginwindow" to «event aevtlogo»'"#) }
        }
        // SwiftUI can keep this view's state from one opening to the next; each opens folded.
        .onChange(of: slot.owner == .apple) { _, open in if !open { forceQuit = false } }
    }

    /// A row that closes the dropdown, then acts.
    private func row(_ title: String, indent: CGFloat = 0, icon: NSImage? = nil, _ action: @escaping () -> Void) -> some View {
        MenuButton {
            slot.dismiss()
            action()
        } content: {
            if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.leading, indent)
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

    private func lockScreen() {
        // The same private call the native "Lock Screen" item uses; there is no public API.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }
}
