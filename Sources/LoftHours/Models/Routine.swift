import Foundation

/// One task inside a routine's checklist, e.g. "🛏️ Make the bed". The emoji is
/// optional flavor; the title is the task. Tasks repeat every time the routine
/// runs, and the per-day tracker records which ones got ticked.
struct RoutineTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var emoji: String = ""
    var title: String = ""

    /// What the checklist row shows: "🛏️ Make the bed", or just the title.
    var displayTitle: String {
        emoji.isEmpty ? title : "\(emoji) \(title)"
    }
}

/// A named recurring time block ("Morning routine ☀️, 7:00, 45 min, daily")
/// with a repeating task checklist. Persisted as JSON in UserDefaults by
/// RoutineService. Runs on its own lightweight countdown (RoutineRunner), and
/// completion is recorded per day by RoutineTracker, never as a session log.
struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    /// Optional emoji shown next to the name everywhere the routine appears.
    var emoji: String = ""
    /// Anchor instant the schedule derives from, exactly like Reminder.anchor:
    /// the time of day, plus the date / weekday / day-of-month the recurrence
    /// needs. Marks the START of the routine's window.
    var anchor: Date = Date()
    /// How long the routine's time block runs.
    var durationMin: Int = 30
    var recurrence: Reminder.Recurrence = .daily
    var enabled: Bool = true
    var customMode: Reminder.CustomMode = .weekdays
    /// Weekday numbers (1 = Sunday ... 7 = Saturday) for `.custom` + `.weekdays`.
    var customWeekdays: Set<Int> = []
    /// Day interval for `.custom` + `.everyNDays`. 2 = every other day.
    var customDays: Int = 2
    var tasks: [RoutineTask] = []
    /// Whether a gentle notification fires when the routine's window opens.
    var notify: Bool = true
    /// The Google Calendar event mirroring this routine (a Free slot spanning
    /// the window), when calendar sync is on.
    var calendarEventId: String? = nil

    /// What the rail, lists, and notifications call this routine.
    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }

    /// The reminder-shaped view of this routine's schedule. All the recurrence
    /// math (triggers, next fire, today's occurrence, RRULE, the monthly day
    /// clamp) lives in Reminder; this proxy keeps it one implementation
    /// instead of two drifting copies.
    var scheduleProxy: Reminder {
        var r = Reminder(kind: .task, title: name, anchor: anchor, recurrence: recurrence)
        r.customMode = customMode
        r.customWeekdays = customWeekdays
        r.customDays = customDays
        return r
    }

    var repeats: Bool { recurrence != .once }

    func monthlyDayClamped(calendar: Calendar = .current) -> Bool {
        scheduleProxy.monthlyDayClamped(calendar: calendar)
    }

    /// Every notification this routine needs, same shapes as Reminder.
    func notificationTriggers(now: Date = Date(), calendar: Calendar = .current) -> [(suffix: String, components: DateComponents, repeats: Bool)] {
        scheduleProxy.notificationTriggers(now: now, calendar: calendar)
    }

    /// The next instant this routine's window opens after `now`.
    func nextFireDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        scheduleProxy.nextFireDate(after: now, calendar: calendar)
    }

    /// Today's window start (past or future), or nil when the routine doesn't
    /// occur today. Drives the "Your day" rail and the start pill.
    func occurrenceToday(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        scheduleProxy.occurrenceToday(now: now, calendar: calendar)
    }

    /// Today's full time window (start...end), or nil when off today.
    func windowToday(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let start = occurrenceToday(now: now, calendar: calendar) else { return nil }
        return start...start.addingTimeInterval(TimeInterval(max(1, durationMin) * 60))
    }

    /// True while `now` sits inside today's window: the moment the home screen
    /// offers the one-click start.
    func isActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        windowToday(now: now, calendar: calendar)?.contains(now) ?? false
    }

    /// Human description of the schedule plus the window length, e.g.
    /// "Daily at 7:00 AM, 45 min".
    func scheduleDescription(calendar: Calendar = .current) -> String {
        "\(scheduleProxy.scheduleDescription(calendar: calendar)), \(durationMin) min"
    }
}

extension Routine {
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, anchor, durationMin, recurrence, enabled
        case customMode, customWeekdays, customDays, tasks, notify, calendarEventId
    }

    /// Hand-rolled with decodeIfPresent defaults, same pattern as Reminder, so
    /// fields added in later versions never wipe saved routines on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        anchor = try c.decode(Date.self, forKey: .anchor)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin) ?? 30
        recurrence = try c.decodeIfPresent(Reminder.Recurrence.self, forKey: .recurrence) ?? .daily
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        customMode = try c.decodeIfPresent(Reminder.CustomMode.self, forKey: .customMode) ?? .weekdays
        customWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .customWeekdays) ?? []
        customDays = try c.decodeIfPresent(Int.self, forKey: .customDays) ?? 2
        tasks = try c.decodeIfPresent([RoutineTask].self, forKey: .tasks) ?? []
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        calendarEventId = try c.decodeIfPresent(String.self, forKey: .calendarEventId)
    }
}
