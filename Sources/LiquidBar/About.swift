import AppKit
import SwiftUI

/// The About LiquidBar window.
final class AboutWindow {
    private var window: NSPanel?

    func show() {
        if window == nil {
            window = glassPanel(NSSize(width: 340, height: 300), close: { [weak self] in self?.close() }) { AboutView(close: { [weak self] in self?.close() }) }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() { window?.orderOut(nil) }
}

private struct AboutView: View {
    let close: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        return "Version \(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "menubar.rectangle").font(.system(size: 40)).padding(.top, 4)
            Text("LiquidBar").font(.system(size: 20, weight: .semibold))
            Text(version).foregroundStyle(secondary)
            Text("A Liquid Glass menu bar for macOS")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            // The panel's white text would otherwise make the link look like plain text.
            Link("github.com/jbroma/liquid-bar", destination: URL(string: "https://github.com/jbroma/liquid-bar")!)
                .foregroundStyle(Color.accentColor)
                .pointerStyle(.link)
            Text("MIT License").foregroundStyle(secondary)
            Spacer(minLength: 0)
            Button("Close", action: close).buttonStyle(.glass).focusEffectDisabled()
        }
        .padding(28)
        .frame(width: 340, height: 300)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
    }
}
