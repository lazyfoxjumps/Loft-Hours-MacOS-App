import Foundation

/// The analytics window: a calendar week or month.
enum ReviewScope: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var title: String { self == .week ? "This Week" : "This Month" }

    /// The calendar interval containing `now` for this scope.
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
    }
}

/// Computed rollup over a window of session logs.
struct Rollup {
    var scope: ReviewScope
    var sessionCount: Int
    var totalFocusMinutes: Int
    var dayStreak: Int
    /// Fraction of sessions that recorded something in `delivered` (0...1).
    var goalDeliveredRatio: Double
    var morningSessions: Int    // start hour < 12
    var afternoonSessions: Int  // 12...16
    var eveningSessions: Int    // >= 17
    var reflections: [String]
    var suggestions: [String]
    /// True when there are fewer than 3 sessions: analytics/suggestions skipped.
    var insufficient: Bool

    var totalFocusHours: Double { Double(totalFocusMinutes) / 60.0 }
    var deliveredCount: Int { Int((goalDeliveredRatio * Double(sessionCount)).rounded()) }
}

/// Reads the log window and produces a `Rollup` plus a saved markdown report,
/// matching the skill's `review week` / `review month` workflow (SKILL §7).
struct RollupService {
    let reader: LogReader

    init(reader: LogReader = LogReader()) {
        self.reader = reader
    }

    func rollup(_ scope: ReviewScope, now: Date, calendar: Calendar = .current) -> Rollup {
        let logs = reader.logs(in: scope.interval(now: now, calendar: calendar))
        let count = logs.count
        let totalMin = logs.reduce(0) { $0 + $1.durationMin }
        let delivered = logs.filter { !$0.delivered.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let ratio = count > 0 ? Double(delivered) / Double(count) : 0

        var morning = 0, afternoon = 0, evening = 0
        for l in logs {
            let h = calendar.component(.hour, from: l.startedAt)
            if h < 12 { morning += 1 } else if h < 17 { afternoon += 1 } else { evening += 1 }
        }

        let reflections = logs.compactMap { $0.reflection.isEmpty ? nil : $0.reflection }
        let streak = Self.dayStreak(logs: logs, now: now, calendar: calendar)
        let insufficient = count < 3
        let suggestions = insufficient
            ? []
            : Self.suggestions(ratio: ratio, morning: morning, afternoon: afternoon, evening: evening)

        return Rollup(
            scope: scope,
            sessionCount: count,
            totalFocusMinutes: totalMin,
            dayStreak: streak,
            goalDeliveredRatio: ratio,
            morningSessions: morning,
            afternoonSessions: afternoon,
            eveningSessions: evening,
            reflections: reflections,
            suggestions: suggestions,
            insufficient: insufficient
        )
    }

    /// Consecutive days with at least one session, counting back from today (or
    /// from yesterday if there's no session yet today, so an active streak isn't
    /// zeroed before the day's first session).
    private static func dayStreak(logs: [ParsedLog], now: Date, calendar: Calendar) -> Int {
        let days = Set(logs.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// 2-3 suggestions grounded strictly in the window's numbers. No fabricated
    /// patterns (SKILL rule).
    private static func suggestions(ratio: Double, morning: Int, afternoon: Int, evening: Int) -> [String] {
        var out: [String] = []
        let pct = Int((ratio * 100).rounded())
        if ratio >= 0.8 {
            out.append("You delivered on \(pct)% of sessions. The goals are sized right, keep them this concrete.")
        } else if ratio <= 0.4 {
            out.append("Only \(pct)% of sessions hit their goal. Try smaller, more concrete goals next week.")
        }
        let top = max(morning, afternoon, evening)
        if top > 0 {
            if morning == top {
                out.append("Most sessions land in the morning. Protect that window for your hardest work.")
            } else if evening == top {
                out.append("You lean on evening sessions. Watch your end-energy on late blocks and stop before it craters.")
            } else {
                out.append("Afternoons are your busiest stretch. Front-load the deep work before the post-lunch dip.")
            }
        }
        return out
    }

    /// Write the markdown report to `<log_dir>/reviews/YYYY-MM-DD-<scope>.md`.
    @discardableResult
    func writeReport(_ rollup: Rollup, now: Date) throws -> URL {
        let dir = reader.logDirectory.appendingPathComponent("reviews", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.formatter("yyyy-MM-dd").string(from: now)
        let url = dir.appendingPathComponent("\(stamp)-\(rollup.scope.rawValue).md")
        try Self.markdown(rollup).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func markdown(_ r: Rollup) -> String {
        var lines: [String] = ["# Review, \(r.scope.title)", ""]
        if r.insufficient {
            lines.append("Only \(r.sessionCount) session\(r.sessionCount == 1 ? "" : "s") in this window. It takes at least 3 to read a pattern, so the analytics are on hold. Come back after a few more.")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        lines.append("- Total focused: \(String(format: "%.1f", r.totalFocusHours)) h")
        lines.append("- Sessions: \(r.sessionCount)")
        lines.append("- Day streak: \(r.dayStreak)")
        lines.append("- Goal delivered: \(r.deliveredCount)/\(r.sessionCount) (\(Int((r.goalDeliveredRatio * 100).rounded()))%)")
        lines.append("- Time of day: \(r.morningSessions) morning, \(r.afternoonSessions) afternoon, \(r.eveningSessions) evening")
        if !r.reflections.isEmpty {
            lines.append("")
            lines.append("## Reflections")
            for ref in r.reflections { lines.append("- \(ref)") }
        }
        if !r.suggestions.isEmpty {
            lines.append("")
            lines.append("## Suggestions")
            for s in r.suggestions { lines.append("- \(s)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
