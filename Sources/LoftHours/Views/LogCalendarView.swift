import SwiftUI

/// The Review > Logs month calendar: a GitHub-contributions-style grid where
/// days with activity (sessions logged + routines completed) get a faint circle
/// behind the day number, stronger with more activity. Tapping a day selects
/// it; the surrounding sheet shows that day's logs + routine status below.
///
/// Pure view: the per-day counts and the selection/month are injected.
struct LogCalendarView: View {
    /// Any date within the displayed month (chevrons step it by a month).
    @Binding var month: Date
    /// The selected day (start of day); the sheet lists this day below the grid.
    @Binding var selected: Date
    /// startOfDay -> activity count (sessions + completed routines).
    let counts: [Date: Int]
    let palette: Palette
    var calendar: Calendar = .current
    var today: Date = Date()

    /// Activity count -> circle opacity. Zero is no circle; then four steps.
    static func intensityOpacity(for count: Int) -> Double {
        switch count {
        case ..<1: return 0
        case 1:    return 0.20
        case 2:    return 0.40
        case 3:    return 0.65
        default:   return 0.90
        }
    }

    /// Merge session logs (one count per day they started) with routine
    /// activity counts into one per-day total the grid draws from.
    static func dayCounts(logs: [ParsedLog], routineCounts: [Date: Int], calendar: Calendar) -> [Date: Int] {
        var out = routineCounts
        for log in logs {
            let day = calendar.startOfDay(for: log.startedAt)
            out[day, default: 0] += 1
        }
        return out
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }

    // MARK: - Header + weekday labels

    private var header: some View {
        HStack {
            chevron("chevron.left", step: -1)
            Spacer()
            Text(monthTitle)
                .font(AppFont.title3)
                .foregroundStyle(palette.foreground)
            Spacer()
            chevron("chevron.right", step: 1)
        }
    }

    private func chevron(_ symbol: String, step: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: step, to: month) {
                month = next
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(AppFont.caption)
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day cell

    private func dayCell(_ day: Date) -> some View {
        let count = counts[day] ?? 0
        let opacity = Self.intensityOpacity(for: count)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let textColor = opacity > 0 ? palette.activityDayTextColor(opacity: opacity) : palette.foreground

        return Button {
            selected = day
        } label: {
            ZStack {
                if opacity > 0 {
                    Circle().fill(palette.activity.opacity(opacity))
                }
                if isToday {
                    Circle().stroke(palette.accent, lineWidth: 1)
                }
                if isSelected {
                    Circle().stroke(palette.activity, lineWidth: 2)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(AppFont.callout)
                    .foregroundStyle(textColor)
            }
            .frame(width: 32, height: 32)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout math

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .current
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: month)
    }

    /// Weekday initials, rotated to the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// One entry per grid slot: leading nils for the blank lead-in, then each
    /// day of the month as its start-of-day date.
    private var cells: [Date?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: month),
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: first) {
                out.append(calendar.startOfDay(for: date))
            }
        }
        return out
    }
}
