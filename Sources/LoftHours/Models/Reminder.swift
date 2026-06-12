import Foundation

/// A user-created reminder: either a task nudge ("pick up the document at 3pm")
/// or a recurring "time to focus" prompt that pulls the user back to the loft.
/// Persisted as JSON in UserDefaults by ReminderService; each reminder maps to
/// one or more scheduled notifications (see `notificationTriggers`).
struct Reminder: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case task
        case focusNudge
    }

    enum Recurrence: String, Codable, CaseIterable, Identifiable {
        case once, daily, weekly, monthly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .once: return "Once"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .custom: return "Custom"
            }
        }
    }

    /// The two shapes a custom schedule can take: a fixed day interval
    /// ("every other day") or a hand-picked set of weekdays ("Mon, Wed, Fri").
    enum CustomMode: String, Codable {
        case everyNDays
        case weekdays
    }

    var id = UUID()
    var kind: Kind = .task
    /// The task text. Unused for focus nudges, whose copy cycles from
    /// `Messages.focusNudges` instead.
    var title: String = ""
    /// Anchor instant the schedule derives from: the exact moment for a one-off,
    /// otherwise the time of day (plus the weekday for weekly, the day of month
    /// for monthly, the count-from day for every-N-days).
    var anchor: Date = Date()
    var recurrence: Recurrence = .once
    var enabled: Bool = true
    var customMode: CustomMode = .weekdays
    /// Weekday numbers (1 = Sunday ... 7 = Saturday) for `.custom` + `.weekdays`.
    var customWeekdays: Set<Int> = []
    /// Day interval for `.custom` + `.everyNDays`. 2 = every other day.
    var customDays: Int = 2
    /// The Google Calendar event mirroring this reminder, when calendar sync is
    /// on. Lets an edit or delete clean up its event instead of orphaning it.
    var calendarEventId: String? = nil

    /// What the timeline and the reminder lists call this reminder.
    var displayTitle: String {
        kind == .focusNudge ? "Time to focus" : title
    }

    var repeats: Bool { recurrence != .once }

    /// Every-N-days can't be expressed as a repeating calendar trigger, so the
    /// service schedules this many one-shot occurrences ahead and refills them
    /// on every launch via `rescheduleAll`.
    static let intervalLookahead = 10

    /// The last day every month is guaranteed to have. Monthly reminders
    /// anchored on the 29th-31st are clamped here, because a calendar trigger
    /// asking for day 31 silently skips the months that don't have one. The
    /// editor flags the clamp to the user.
    static let monthlyDayCap = 28

    /// True when this monthly reminder's anchor day gets clamped to the cap.
    func monthlyDayClamped(calendar: Calendar = .current) -> Bool {
        recurrence == .monthly && calendar.component(.day, from: anchor) > Self.monthlyDayCap
    }

    /// The date components for a single UNCalendarNotificationTrigger. Custom
    /// recurrences need several triggers; use `notificationTriggers` for those.
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
        case .daily, .custom:
            break
        case .weekly:
            c.weekday = all.weekday
        case .monthly:
            c.day = min(all.day ?? 1, Self.monthlyDayCap)
        }
        return c
    }

    /// Every notification this reminder needs, as (identifier suffix, trigger
    /// components, repeats). The simple recurrences are one repeating trigger;
    /// custom weekdays are one repeating trigger per picked day; every-N-days
    /// is a rolling window of one-shot triggers.
    func notificationTriggers(now: Date = Date(), calendar: Calendar = .current) -> [(suffix: String, components: DateComponents, repeats: Bool)] {
        switch recurrence {
        case .once, .daily, .weekly, .monthly:
            return [("", triggerComponents(calendar: calendar), repeats)]
        case .custom:
            switch customMode {
            case .weekdays:
                let time = calendar.dateComponents([.hour, .minute], from: anchor)
                return customWeekdays.sorted().map { weekday in
                    var c = time
                    c.weekday = weekday
                    return (".wd\(weekday)", c, true)
                }
            case .everyNDays:
                return upcomingIntervalDates(after: now, calendar: calendar, count: Self.intervalLookahead)
                    .enumerated()
                    .map { i, date in
                        (".d\(i)", calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), false)
                    }
            }
        }
    }

    /// The next `count` fire instants of an every-N-days schedule after `now`,
    /// stepping `customDays` from the anchor's day at the anchor's time.
    func upcomingIntervalDates(after now: Date = Date(), calendar: Calendar = .current, count: Int) -> [Date] {
        let n = max(1, customDays)
        let hour = calendar.component(.hour, from: anchor)
        let minute = calendar.component(.minute, from: anchor)
        let anchorDay = calendar.startOfDay(for: anchor)
        let nowDay = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: anchorDay, to: nowDay).day ?? 0
        // First multiple of n on or after today.
        var k = days <= 0 ? 0 : (days + n - 1) / n
        var out: [Date] = []
        while out.count < count {
            guard let day = calendar.date(byAdding: .day, value: k * n, to: anchorDay),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { break }
            if fire > now { out.append(fire) }
            k += 1
        }
        return out
    }

    /// The next instant this fires after `now`, or nil for a one-off already in
    /// the past (or a custom-weekdays reminder with no days picked). Drives the
    /// reminder lists and the launch-time reschedule guard.
    func nextFireDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch recurrence {
        case .once:
            return anchor > now ? anchor : nil
        case .custom:
            switch customMode {
            case .weekdays:
                let time = calendar.dateComponents([.hour, .minute], from: anchor)
                return customWeekdays.compactMap { weekday -> Date? in
                    var c = time
                    c.weekday = weekday
                    return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
                }.min()
            case .everyNDays:
                return upcomingIntervalDates(after: now, calendar: calendar, count: 1).first
            }
        case .daily, .weekly, .monthly:
            return calendar.nextDate(after: now, matching: triggerComponents(calendar: calendar), matchingPolicy: .nextTime)
        }
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
        case .custom:
            switch customMode {
            case .weekdays:
                guard customWeekdays.contains(calendar.component(.weekday, from: now)) else { return nil }
            case .everyNDays:
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: anchor),
                    to: calendar.startOfDay(for: now)
                ).day ?? 0
                guard days >= 0, days % max(1, customDays) == 0 else { return nil }
            }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// Human description of the schedule for the reminder lists, e.g.
    /// "Daily at 9:00 AM" or "Mon, Wed, Fri at 9:00 AM".
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
        case .custom:
            switch customMode {
            case .everyNDays:
                let n = max(1, customDays)
                return n == 1 ? "Daily at \(time)" : "Every \(n) days at \(time)"
            case .weekdays:
                if customWeekdays.count == 7 { return "Daily at \(time)" }
                if customWeekdays.isEmpty { return "No days picked yet" }
                let names = customWeekdays.sorted().map { timeFmt.shortWeekdaySymbols[$0 - 1] }
                return "\(names.joined(separator: ", ")) at \(time)"
            }
        }
    }
}

extension Reminder {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, anchor, recurrence, enabled
        case customMode, customWeekdays, customDays, calendarEventId
    }

    /// Hand-rolled so blobs saved before the custom-recurrence and calendar
    /// fields existed still decode (missing keys fall back to the defaults)
    /// instead of silently wiping the user's reminders on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        anchor = try c.decode(Date.self, forKey: .anchor)
        recurrence = try c.decode(Recurrence.self, forKey: .recurrence)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        customMode = try c.decodeIfPresent(CustomMode.self, forKey: .customMode) ?? .weekdays
        customWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .customWeekdays) ?? []
        customDays = try c.decodeIfPresent(Int.self, forKey: .customDays) ?? 2
        calendarEventId = try c.decodeIfPresent(String.self, forKey: .calendarEventId)
    }
}
