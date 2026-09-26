import AppKit
import LiquidBarCore
import SwiftUI

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
