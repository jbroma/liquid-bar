import AppKit
import SwiftUI

/// Asks for Accessibility access and follows the grant, which macOS gives no notification for.
@Observable
final class AccessWindow {
    private(set) var granted = AXIsProcessTrusted()
    @ObservationIgnored private var window: NSPanel?
    @ObservationIgnored private var poll: Timer?
    /// Runs once when the grant arrives while the window is open, to restart what needed it.
    @ObservationIgnored private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) { self.onGranted = onGranted }

    /// Adds the app to the Accessibility list, shows macOS's prompt, and opens the list.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
    }

    func show() {
        granted = AXIsProcessTrusted()
        if window == nil {
            let panel = glassPanel(NSSize(width: 440, height: 380), close: { [weak self] in self?.close() }) { AccessView(state: self, close: { [weak self] in self?.close() }) }
            window = panel
        }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func check() {
        guard !granted, AXIsProcessTrusted() else { return }
        granted = true
        poll?.invalidate()
        onGranted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.close() }
    }

    func close() {
        poll?.invalidate()
        window?.orderOut(nil)
    }
}

/// A borderless glass window centred on screen, which `content` fills. Esc calls `close`.
func glassPanel<Content: View>(_ size: NSSize, close: @escaping () -> Void, content: () -> Content) -> NSPanel {
    let panel = OnboardingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    panel.onCancel = close
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    let host = NSHostingView(rootView: content())
    host.sizingOptions = []
    panel.contentView = host
    panel.center()
    return panel
}

/// A borderless window refuses key status unless it says otherwise, and its buttons need the first click.
private final class OnboardingPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

private struct AccessView: View {
    let state: AccessWindow
    let close: () -> Void
    private let uses = [
        "The front app's menus in the bar",
        "Other apps' menu bar items",
        "Control Center's Focus, AirDrop, and Bluetooth options",
        "Switching desktops with the bar",
    ]

    var body: some View {
        VStack(spacing: 16) {
            if state.granted { grantedBody } else { requestBody }
        }
        .padding(28)
        .frame(width: 440, height: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
        .animation(.easeOut(duration: 0.2), value: state.granted)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(uses, id: \.self) { use in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(secondary)
                    Text(use)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var requestBody: some View {
        Image(systemName: "hand.raised.fill").font(.system(size: 34)).padding(.top, 4)
        Text("Allow Accessibility").font(.system(size: 20, weight: .semibold))
        Text("LiquidBar covers the menu bar, so it needs Accessibility access to read and press what is under it.")
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        list.padding(.top, 4)
        Spacer(minLength: 0)
        Button("Open Accessibility Settings") { AccessWindow.requestAccess() }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        Button("Not Now", action: close)
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(secondary)
    }

    @ViewBuilder private var grantedBody: some View {
        Spacer(minLength: 0)
        Image(systemName: "checkmark.circle.fill").font(.system(size: 44))
        Text("You're all set").font(.system(size: 20, weight: .semibold))
        Text("LiquidBar has Accessibility access.").foregroundStyle(secondary)
        Spacer(minLength: 0)
        Button("Open Accessibility Settings") { AccessWindow.requestAccess() }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(secondary)
        Button("Close", action: close)
            .buttonStyle(.glass)
    }
}
