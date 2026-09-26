import LiquidBarCore
import SwiftUI

/// The full date over a month grid with week numbers and today marked. Scroll or the chevrons change the month.
struct ClockMenu: View {
    let now: Date
    @State private var month = Date()
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let days = monthGrid(for: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        MenuBody {
            MenuTitle(title: fullDateText(now))
            MenuSeparator()
            MenuRow {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 2) {
                    MonthButton(symbol: "chevron.left") { shift(-1) }
                    MonthButton(symbol: "circle.fill", size: 6) { withAnimation(spring) { month = Date() } }
                        .help("Today")
                    MonthButton(symbol: "chevron.right") { shift(1) }
                }
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("").frame(width: 22)
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).frame(width: 30)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondary)
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
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .overlay { ScrollCatcher(step: 30) { shift($0 > 0 ? -1 : 1) } }
    }

    private func dayCell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Text("\(calendar.component(.day, from: day))")
            .fontWeight(today ? .bold : .medium)
            .frame(width: 30, height: 24)
            .foregroundStyle(today ? Color.black : Color.barWhite.opacity(inMonth ? 1 : 0.3))
            .background { if today { Circle().fill(Color.barWhite).frame(width: 24, height: 24) } }
    }

    private func shift(_ months: Int) {
        withAnimation(spring) { month = calendar.date(byAdding: .month, value: months, to: month)! }
    }
}

private struct MonthButton: View {
    let symbol: String
    var size: CGFloat = 11
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 24, height: 22)
            .background { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.12 : 0)) }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}
