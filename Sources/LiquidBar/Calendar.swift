import LiquidBarCore
import SwiftUI

/// Today as a headline, over a month grid with week numbers and today marked. Scroll or the chevrons change the
/// month, which slides in from the side it comes from.
struct ClockMenu: View {
    let now: Date
    @Environment(ExpansionSlot.self) private var slot
    @State private var month = Date()
    /// The way the last change went, for the slide: 1 is forward.
    @State private var direction = 1
    @State private var hovered: Date?
    private let calendar = Calendar.autoupdatingCurrent
    /// The red of Apple's Calendar, which it keeps whatever the accent colour.
    private static let red = Color(nsColor: .systemRed)

    var body: some View {
        let days = monthGrid(for: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 }
        let current = calendar.isDate(month, equalTo: now, toGranularity: .month)
        MenuBody {
            // Like Calendar's widget: the weekday in Calendar's red over a large, light day number.
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: -3) {
                    Text(now.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Self.red)
                    Text(now.formatted(.dateTime.day())).font(.system(size: 34, weight: .light)).monospacedDigit()
                }
                Spacer(minLength: 8)
                Text("Week \(calendar.component(.weekOfYear, from: now))").font(.system(size: 11)).foregroundStyle(secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            MenuSeparator()
            MenuRow {
                // As Calendar titles a month: the month in bold, the year after it in regular.
                (Text(month.formatted(.dateTime.month(.wide))).fontWeight(.bold) + Text(" " + month.formatted(.dateTime.year())))
                    .font(.system(size: 15))
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 2) {
                    MonthButton(symbol: "chevron.left") { shift(-1) }
                    // Back to today, lit only while another month shows.
                    MonthButton(symbol: "circle.fill", size: 6) { show(Date()) }
                        .foregroundStyle(current ? secondary : Self.red)
                        .help("Today")
                    MonthButton(symbol: "chevron.right") { shift(1) }
                }
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("").frame(width: 22)
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { column, weekday in
                        Text(symbols[weekday]).frame(width: 30).opacity(calendar.isDateInWeekend(days[column]) ? 0.6 : 1)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondary)
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        Text("\(calendar.component(.weekOfYear, from: days[row * 7]))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.barWhite.opacity(0.3))
                            .frame(width: 22)
                        ForEach(days[row * 7 ..< row * 7 + 7], id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .id(calendar.dateComponents([.year, .month], from: month))
            .transition(.asymmetric(insertion: .offset(x: CGFloat(direction) * 40).combined(with: .opacity),
                                    removal: .offset(x: CGFloat(-direction) * 40).combined(with: .opacity)))
            MenuSeparator()
            MenuButton {
                slot.dismiss()
                shell("open -b com.apple.iCal")
            } content: { Text("Open Calendar") }
        }
        .clipped()
        .overlay { ScrollCatcher(step: 30) { shift($0 > 0 ? -1 : 1) } }
        .onChange(of: slot.owner == .clock) { _, open in if !open { month = Date() } }
    }

    private func dayCell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let weekend = calendar.isDateInWeekend(day)
        return Text("\(calendar.component(.day, from: day))")
            .fontWeight(today ? .semibold : .regular)
            .frame(width: 30, height: 26)
            .foregroundStyle(today ? Color.white : Color.barWhite.opacity(!inMonth ? 0.22 : weekend ? 0.55 : 1))
            .background {
                if today {
                    // Calendar marks today with a flat red circle.
                    Circle().fill(Self.red).frame(width: 24, height: 24)
                } else {
                    Circle().fill(.white.opacity(hovered == day ? 0.12 : 0)).frame(width: 25, height: 25)
                }
            }
            .onHover { if $0 { hovered = day } else if hovered == day { hovered = nil } }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func shift(_ months: Int) {
        show(calendar.date(byAdding: .month, value: months, to: month)!)
    }

    private func show(_ date: Date) {
        direction = date < month ? -1 : 1
        withAnimation(spring) { month = date }
    }
}

private struct MonthButton: View {
    let symbol: String
    var size: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 24, height: 22)
            .hoverButton(radius: 6, action: action)
    }
}
