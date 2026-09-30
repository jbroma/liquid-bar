import AppKit
import SwiftUI

/// LiquidBar's own menu, which a secondary click on the bar opens: a small panel in the dropdown glass hanging below
/// the bar at the pointer. A click outside it or Esc closes it.
final class BarMenu {
    private var panel: NSPanel?
    private var monitors: [Any] = []

    /// `point` is the pointer in screen coordinates, `barBottom` the bar's lower edge.
    func show(at point: NSPoint, below barBottom: CGFloat) {
        close()
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.frame ?? .zero
        // Each row is 24pt; the padding and the separator take 26pt.
        let size = NSSize(width: 220, height: delegate.updates.updater == nil ? 74 : 98)
        let x = min(max(point.x - 14, screen.minX + 6), screen.maxX - size.width - 6)
        let panel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: x, y: barBottom - 6 - size.height), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .init(rawValue: barLevel.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: BarMenuView { [weak self] in self?.close() })
        panel.orderFrontRegardless()
        self.panel = panel
        let outside: (NSEvent) -> Void = { [weak self] event in
            guard event.window != self?.panel else { return }
            MainActor.assumeIsolated { self?.close() }
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside),
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { outside($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                MainActor.assumeIsolated { self?.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self else { return event }
                close()
                return nil
            },
        ].compactMap { $0 }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct BarMenuView: View {
    let close: () -> Void

    var body: some View {
        MenuBody {
            if delegate.updates.updater != nil {
                row("Check for Updates…") { delegate.updates.check() }
            }
            row("LiquidBar Settings…") { delegate.settings.show() }
            MenuSeparator()
            row("Quit LiquidBar") { delegate.quit() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OverlayGlass(corner: DropdownView.corner))
        .font(.system(size: 13))
        .foregroundStyle(Color.barWhite)
    }

    private func row(_ title: String, _ action: @escaping () -> Void) -> some View {
        MenuButton {
            close()
            action()
        } content: {
            Text(title)
            Spacer(minLength: 8)
        }
    }
}
