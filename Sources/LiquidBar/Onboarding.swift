import AppKit
import SwiftUI

/// Asks for Accessibility access and follows the grant, which macOS gives no notification for.
@Observable
final class AccessWindow {
    private(set) var granted = AXIsProcessTrusted()
    /// The request is out; the window shows a waiting state until the grant arrives.
    private(set) var waiting = false
    /// macOS's own prompt is up, so the window points at its button rather than at the list.
    private(set) var prompted = false
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var poll: Timer?
    /// Runs once when the grant arrives while the window is open or a request waits, to restart what needed it.
    @ObservationIgnored private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) { self.onGranted = onGranted }

    /// Adds the app to the Accessibility list and shows macOS's prompt, whose button opens the list. Opening the list
    /// as well would race the prompt, so the list opens here only when macOS shows no prompt, as after a Deny.
    /// `prompted` tells whether the prompt is up.
    static func requestAccess(prompted: @escaping (Bool) -> Void = { _ in }) {
        UserDefaults.standard.set(true, forKey: Permission.askedAccessibility)
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let shown = windows.contains { $0[kCGWindowOwnerName as String] as? String == "universalAccessAuthWarn" }
            if !shown { shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'") }
            prompted(shown)
        }
    }

    /// Asks without the window, from the Settings window or a bar item that needs access, and follows the grant.
    func request() {
        Self.requestAccess { [weak self] shown in self?.prompted = shown }
        watch()
    }

    /// Asks through macOS's prompt and waits in place: the window stays a normal one, so System Settings and the
    /// prompt open above it.
    func openSettings() {
        request()
        waiting = !granted
    }

    func show() {
        granted = AXIsProcessTrusted()
        waiting = false
        if window == nil {
            let content = NSHostingController(rootView: AccessView(state: self, close: { [weak self] in self?.close() }))
            let window = AppWindow(contentViewController: content)
            window.styleMask = [.titled, .closable]
            // Centring needs the final size, which the hosting controller only reports after layout.
            window.setContentSize(content.view.fittingSize)
            window.title = ""
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.appearance = systemAppearance()
        watch()
        window.map(bringForward)
    }

    private func watch() {
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
        poll?.invalidate()
        onGranted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.close() }
    }

    /// The poll keeps going until the grant arrives, so a grant made later still restarts what needed it.
    func close() {
        window?.close()
    }
}

private struct AccessView: View {
    let state: AccessWindow
    let close: () -> Void
    private let uses: [(symbol: String, tint: Color, text: String)] = [
        ("menubar.rectangle", .blue, "Show the front app's menus in the bar"),
        ("square.grid.2x2.fill", .orange, "Show other apps' menu bar items"),
        ("switch.2", .gray, "Use Control Center's Focus, AirDrop, and Bluetooth"),
        ("rectangle.3.group.fill", .purple, "Switch desktops from the bar"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            if state.granted { grantedBody } else if state.waiting { waitingBody } else { requestBody }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(width: 480)
        .animation(.easeOut(duration: 0.2), value: state.granted)
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title2.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var requestBody: some View {
        heading("LiquidBar Needs Accessibility Access", "LiquidBar covers the menu bar, so it needs Accessibility access to read and press what is under it.")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(uses, id: \.text) { use in
                HStack(spacing: 12) {
                    IconTile(symbol: use.symbol, tint: use.tint, size: 28)
                    Text(use.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        HStack {
            Spacer()
            Button("Not Now", action: close).keyboardShortcut(.cancelAction).focusEffectDisabled()
            Button("Open System Settings") { state.openSettings() }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var waitingBody: some View {
        heading("Turn On LiquidBar in the Accessibility List", state.prompted
            ? "Click Open System Settings in the macOS dialog, then switch on LiquidBar. This window closes once it is on."
            : "Switch on LiquidBar in System Settings. This window closes once it is on.")
        ProgressView().controlSize(.small).padding(.vertical, 8)
        HStack {
            Spacer()
            Button("Close", action: close).keyboardShortcut(.cancelAction).focusEffectDisabled()
        }
    }

    private var grantedBody: some View {
        heading("You're All Set", "LiquidBar has Accessibility access.")
    }
}
