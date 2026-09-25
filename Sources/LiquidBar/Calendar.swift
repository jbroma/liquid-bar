import AppKit
import LiquidBarCore
import SwiftUI

/// The glass month calendar below the clock, in its own child panel so the bar window keeps its height.
@MainActor
enum CalendarPopover {
    private static var panel: KeyPanel?
    private static var monitors: [Any] = []

    static func toggle(anchor: NSRect) {
        if panel != nil { close() } else { open(anchor: anchor) }
    }

    private static func open(anchor: NSRect) {
        let host = NSHostingView(rootView: CalendarView(onClose: close))
        let size = host.fittingSize
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        // Right-aligned with the clock, kept on screen.
        let x = min(max(anchor.maxX - size.width, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let panel = KeyPanel(contentRect: NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        NSApp.windows.first { $0 !== panel && $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }?
            .addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        // Any click elsewhere closes it; clicks on the clock itself go to its toggle.
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { close() }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                if event.window !== panel, !anchor.contains(NSEvent.mouseLocation) { close() }
                return event
            } as Any,
        ]
    }

    static func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.parent?.removeChildWindow(panel!)
        panel?.close()
        panel = nil
    }
}

/// Borderless panels refuse key status by default; the calendar takes it so Esc and arrow keys reach it.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct CalendarView: View {
    let onClose: () -> Void
    @State private var month = Date()
    @State private var appeared = false
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let days = monthGrid(for: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.numericText())
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button { month = Date() } label: { Circle().frame(width: 6, height: 6) }
                    .help("Today")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("").frame(width: 22)
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).frame(width: 30)
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.barWhite.opacity(0.5))
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        Text("\(calendar.component(.weekOfYear, from: days[row * 7]))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.barWhite.opacity(0.35))
                            .frame(width: 22)
                        ForEach(days[row * 7 ..< row * 7 + 7], id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay { ScrollCatcher(step: 30) { shift($0 > 0 ? -1 : 1) } }
        .scaleEffect(appeared ? 1 : 0.92, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(spring) { appeared = true } }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.leftArrow) { shift(-1); return .handled }
        .onKeyPress(.rightArrow) { shift(1); return .handled }
        .focusable()
        .focusEffectDisabled()
        .padding(8)
    }

    private func dayCell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Text("\(calendar.component(.day, from: day))")
            .frame(width: 30, height: 26)
            .foregroundStyle(today ? Color.black : Color.barWhite.opacity(inMonth ? 1 : 0.3))
            .background { if today { Capsule().fill(Color.barWhite) } }
    }

    private func shift(_ months: Int) {
        withAnimation(spring) { month = calendar.date(byAdding: .month, value: months, to: month)! }
    }
}
