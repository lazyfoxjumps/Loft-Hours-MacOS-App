import Foundation

/// A user-created reminder: either a task nudge ("pick up the document at 3pm")
/// or a recurring "time to focus" prompt that pulls the user back to the loft.
/// Persisted as JSON in UserDefaults by ReminderService; each reminder maps to
/// a single UNCalendarNotificationTrigger.
struct Reminder: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case task
        case focusNudge
    }

    enum Recurrence: String, Codable, CaseIterable, Identifiable {
        case once, daily, weekly, monthly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .once: return "Once"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .task
    /// The task text. Unused for focus nudges, whose copy cycles from
    /// `Messages.focusNudges` instead.
    var title: String = ""
    /// Anchor instant the schedule derives from: the exact moment for a one-off,
    /// otherwise the time of day (plus the weekday for weekly, the day of month
    /// for monthly).
    var anchor: Date = Date()
    var recurrence: Recurrence = .once
    var enabled: Bool = true

    /// What the timeline and the Settings list call this reminder.
    var displayTitle: String {
        kind == .focusNudge ? "Time to focus" : title
    }

    var repeats: Bool { recurrence != .once }

    /// The last day every month is guaranteed to have. Monthly reminders
    /// anchored on the 29th-31st are clamped here, because a calendar trigger
    /// asking for day 31 silently skips the months that don't have one. The
    /// editor flags the clamp to the user.
    static let monthlyDayCap = 28

    /// True when this monthly reminder's anchor day gets clamped to the cap.
    func monthlyDayClamped(calendar: Calendar = .current) -> Bool {
        recurrence == .monthly && calendar.component(.day, from: anchor) > Self.monthlyDayCap
    }

    /// The date components for this reminder's UNCalendarNotificationTrigger.
    func triggerComponents(calendar: Calendar = .current) -> DateComponents {
        let all = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: anchor)
        var c = DateComponents()
        c.hour = all.hour
        c.minute = all.minute
        switch recurrence {
        case .once:
            c.year = all.year
            c.month = all.month
            c.day = all.day
        case .daily:
            break
        case .weekly:
            c.weekday = all.weekday
        case .monthly:
            c.day = min(all.day ?? 1, Self.monthlyDayCap)
        }
        return c
    }

    /// The next instant this fires after `now`, or nil for a one-off already in
    /// the past. Drives the Settings list and the launch-time reschedule guard.
    func nextFireDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        if recurrence == .once {
            return anchor > now ? anchor : nil
        }
        return calendar.nextDate(after: now, matching: triggerComponents(calendar: calendar), matchingPolicy: .nextTime)
    }

    /// Today's occurrence of this reminder (past or future), or nil when it
    /// doesn't fire today. The "Your day" timeline shows exactly these.
    func occurrenceToday(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let hour = calendar.component(.hour, from: anchor)
        let minute = calendar.component(.minute, from: anchor)
        switch recurrence {
        case .once:
            return calendar.isDate(anchor, inSameDayAs: now) ? anchor : nil
        case .daily:
            break
        case .weekly:
            guard calendar.component(.weekday, from: now) == calendar.component(.weekday, from: anchor) else { return nil }
        case .monthly:
            let day = min(calendar.component(.day, from: anchor), Self.monthlyDayCap)
            guard calendar.component(.day, from: now) == day else { return nil }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// Human description of the schedule for the Settings list, e.g.
    /// "Daily at 9:00 AM" or "Weekly on Monday at 9:00 AM".
    func scheduleDescription(calendar: Calendar = .current) -> String {
        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        let time = timeFmt.string(from: anchor)
        switch recurrence {
        case .once:
            let dateFmt = DateFormatter()
            dateFmt.calendar = calendar
            dateFmt.dateStyle = .medium
            dateFmt.timeStyle = .none
            return "Once, \(dateFmt.string(from: anchor)) at \(time)"
        case .daily:
            return "Daily at \(time)"
        case .weekly:
            let weekday = calendar.component(.weekday, from: anchor)
            let name = timeFmt.weekdaySymbols[weekday - 1]
            return "Weekly on \(name) at \(time)"
        case .monthly:
            let day = min(calendar.component(.day, from: anchor), Self.monthlyDayCap)
            return "Monthly on day \(day) at \(time)"
        }
    }
}
