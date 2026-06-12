import Foundation

/// Outcome of a calendar write. The session path ignores it (best-effort), but
/// the Settings "Send test event" button surfaces it so failures aren't silent.
enum CalendarSendResult {
    case created(id: String)
    case notConnected
    case failed(status: Int, body: String)
    case transportError(String)

    /// Short human-readable summary for the Settings status line.
    var summary: String {
        switch self {
        case .created: return "Test event created. Check your calendar."
        case .notConnected: return "Not connected to Google."
        case .failed(let status, let body):
            let trimmed = body.count > 240 ? String(body.prefix(240)) + "..." : body
            return "Google rejected it (HTTP \(status)): \(trimmed)"
        case .transportError(let msg): return "Network error: \(msg)"
        }
    }
}

/// Creates a "busy" Google Calendar event for a single focus block.
///
/// Best-effort, like FocusService: in the session path every failure is
/// swallowed so a calendar hiccup can't break or delay the timer. Finished
/// blocks are left on the calendar by design; this service only creates.
struct CalendarService {
    let auth: GoogleAuth
    var calendarId: String = "primary"

    /// Fire-and-forget convenience used by the session path. Returns the event
    /// id or nil; discards all error detail.
    @discardableResult
    func createBlockEvent(title: String, start: Date, durationMin: Int) async -> String? {
        if case .created(let id) = await send(title: title, start: start, durationMin: durationMin) {
            return id
        }
        return nil
    }

    // MARK: - Pure helpers (testable without network)

    /// The event title for a block: "Loft Hours - <goal>", or just "Loft Hours"
    /// when there's no goal. Used by both the session path and `send`.
    static func eventTitle(forGoal goal: String) -> String {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Loft Hours" : "Loft Hours - \(trimmed)"
    }

    /// The Google Calendar event JSON body for one block. Busy/opaque, no
    /// calendar pop-up reminders (the app already runs the timer), explicit
    /// timezone so DST/travel can't shift the slot.
    static func eventBody(title: String, start: Date, durationMin: Int, timeZone: String) -> [String: Any] {
        let end = start.addingTimeInterval(TimeInterval(durationMin * 60))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return [
            "summary": title,
            "start": ["dateTime": formatter.string(from: start), "timeZone": timeZone],
            "end": ["dateTime": formatter.string(from: end), "timeZone": timeZone],
            "transparency": "opaque",
            "reminders": ["useDefault": false],
            "description": "Created by Loft Hours",
        ]
    }

    // MARK: - Reminder events

    /// The RFC 5545 recurrence rule matching a reminder's schedule, or nil for
    /// a one-off (or a weekday set with nothing picked). Pure, selftest-covered.
    static func recurrenceRule(for reminder: Reminder, calendar: Calendar = .current) -> String? {
        switch reminder.recurrence {
        case .once:
            return nil
        case .daily:
            return "RRULE:FREQ=DAILY"
        case .weekly:
            return "RRULE:FREQ=WEEKLY;BYDAY=\(byDay(calendar.component(.weekday, from: reminder.anchor)))"
        case .monthly:
            let day = min(calendar.component(.day, from: reminder.anchor), Reminder.monthlyDayCap)
            return "RRULE:FREQ=MONTHLY;BYMONTHDAY=\(day)"
        case .custom:
            switch reminder.customMode {
            case .everyNDays:
                return "RRULE:FREQ=DAILY;INTERVAL=\(max(1, reminder.customDays))"
            case .weekdays:
                guard !reminder.customWeekdays.isEmpty else { return nil }
                let days = reminder.customWeekdays.sorted().map(byDay).joined(separator: ",")
                return "RRULE:FREQ=WEEKLY;BYDAY=\(days)"
            }
        }
    }

    /// RFC 5545 weekday code for a Calendar weekday number (1 = Sunday).
    private static func byDay(_ weekday: Int) -> String {
        ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][(weekday - 1 + 7) % 7]
    }

    /// The event JSON for a reminder: a short free ("transparent") slot at the
    /// fire time with a popup at 0 minutes, so Google surfaces it like a
    /// reminder instead of blocking the calendar as busy time.
    static func reminderEventBody(_ reminder: Reminder, start: Date, timeZone: String, calendar: Calendar = .current) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let end = start.addingTimeInterval(15 * 60)
        var body: [String: Any] = [
            "summary": eventTitle(forGoal: reminder.displayTitle),
            "start": ["dateTime": formatter.string(from: start), "timeZone": timeZone],
            "end": ["dateTime": formatter.string(from: end), "timeZone": timeZone],
            "transparency": "transparent",
            "reminders": ["useDefault": false, "overrides": [["method": "popup", "minutes": 0]]],
            "description": "Reminder created by Loft Hours",
        ]
        if let rule = recurrenceRule(for: reminder, calendar: calendar) {
            body["recurrence"] = [rule]
        }
        return body
    }

    // MARK: - Routine events

    /// The event JSON for a routine: a slot spanning the routine's full window
    /// (start time + duration), recurring with its schedule, and always
    /// transparent ("Free"), never opaque, because a routine shouldn't block
    /// the calendar the way a focus block does. No calendar pop-ups either;
    /// the app's own nudge covers that.
    static func routineEventBody(_ routine: Routine, start: Date, timeZone: String, calendar: Calendar = .current) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let end = start.addingTimeInterval(TimeInterval(max(1, routine.durationMin) * 60))
        var body: [String: Any] = [
            "summary": eventTitle(forGoal: routine.displayName),
            "start": ["dateTime": formatter.string(from: start), "timeZone": timeZone],
            "end": ["dateTime": formatter.string(from: end), "timeZone": timeZone],
            "transparency": "transparent",
            "reminders": ["useDefault": false],
            "description": "Routine created by Loft Hours",
        ]
        if let rule = recurrenceRule(for: routine.scheduleProxy, calendar: calendar) {
            body["recurrence"] = [rule]
        }
        return body
    }

    /// Create the calendar event mirroring a routine. Returns the event id, or
    /// nil when not connected, nothing left to fire, or Google rejected it.
    func createRoutineEvent(_ routine: Routine) async -> String? {
        guard let start = routine.nextFireDate() else { return nil }
        let body = Self.routineEventBody(routine, start: start, timeZone: TimeZone.current.identifier)
        return await postEvent(body)
    }

    /// Create the calendar event mirroring a reminder. Returns the event id, or
    /// nil when not connected, nothing left to fire, or Google rejected it.
    func createReminderEvent(_ reminder: Reminder) async -> String? {
        guard let start = reminder.nextFireDate() else { return nil }
        let body = Self.reminderEventBody(reminder, start: start, timeZone: TimeZone.current.identifier)
        return await postEvent(body)
    }

    /// Delete an event by id. Best-effort: a 404 (already gone) or any network
    /// failure is silently ignored.
    func deleteEvent(id: String) async {
        guard let token = await auth.accessToken(),
              let url = eventsURL(suffix: "/" + id) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    /// POST an event body to the calendar; returns the created event's id.
    private func postEvent(_ body: [String: Any]) async -> String? {
        guard let token = await auth.accessToken(),
              let url = eventsURL(),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["id"] as? String
    }

    private func eventsURL(suffix: String = "") -> URL? {
        let encodedCalendar = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        return URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendar)/events\(suffix)")
    }

    /// Full diagnostic create. Used by the Settings test button.
    func send(title: String, start: Date, durationMin: Int) async -> CalendarSendResult {
        guard let token = await auth.accessToken() else { return .notConnected }

        let body = Self.eventBody(title: title, start: start, durationMin: durationMin, timeZone: TimeZone.current.identifier)

        let encodedCalendar = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendar)/events"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return .transportError("Could not build request.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .transportError("No HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failed(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "<no body>")
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return .created(id: (json?["id"] as? String) ?? "(no id)")
        } catch {
            return .transportError(error.localizedDescription)
        }
    }
}
