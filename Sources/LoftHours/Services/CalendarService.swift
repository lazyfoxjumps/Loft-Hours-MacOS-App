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
