import Foundation
import UserNotifications

/// Owns the user's reminders: persists them as one JSON blob in UserDefaults
/// and mirrors each enabled one into scheduled local notifications. Identifiers
/// derive from the reminder id, so re-scheduling the same reminder replaces
/// instead of duplicating. When Google Calendar sync is on, each reminder is
/// also mirrored to a calendar event (recurring where the schedule allows).
@MainActor
final class ReminderService: ObservableObject {
    @Published private(set) var reminders: [Reminder]

    private let defaults: UserDefaults
    private let auth: GoogleAuth?
    private let config: ConfigStore?
    private static let key = "lofthours.reminders"
    private static let idPrefix = "lofthours.reminder."

    init(defaults: UserDefaults = .standard, auth: GoogleAuth? = nil, config: ConfigStore? = nil) {
        self.defaults = defaults
        self.auth = auth
        self.config = config
        self.reminders = Self.decode(defaults.data(forKey: Self.key))
    }

    // MARK: - CRUD

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        persist()
        schedule(reminder)
        syncCalendarEvent(for: reminder.id)
    }

    func update(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        // Keep the event link the row already has; the editor's draft carries it
        // too, but belt and braces.
        var updated = reminder
        updated.calendarEventId = updated.calendarEventId ?? reminders[idx].calendarEventId
        reminders[idx] = updated
        persist()
        cancel(reminder.id)
        schedule(updated)
        syncCalendarEvent(for: reminder.id)
    }

    func remove(_ id: UUID) {
        let eventId = reminders.first(where: { $0.id == id })?.calendarEventId
        reminders.removeAll { $0.id == id }
        persist()
        cancel(id)
        deleteCalendarEvent(eventId)
    }

    func setEnabled(_ on: Bool, id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].enabled = on
        persist()
        cancel(id)
        if on { schedule(reminders[idx]) }
        syncCalendarEvent(for: id)
    }

    /// Re-mirror every reminder into the notification center. Called once at
    /// launch: identifiers are stable so this replaces rather than duplicates,
    /// it re-rolls the focus-nudge copy, and it refills the rolling window of
    /// every-N-days one-shots. Calendar events are left alone (already there).
    func rescheduleAll() {
        for reminder in reminders {
            cancel(reminder.id)
            schedule(reminder)
        }
    }

    // MARK: - Notification mirroring

    private func schedule(_ reminder: Reminder) {
        guard reminder.enabled else { return }
        // Nothing left to fire: a one-off in the past, or a custom-weekdays
        // reminder with no days picked.
        guard reminder.nextFireDate() != nil else { return }
        let base = Self.idPrefix + reminder.id.uuidString
        for t in reminder.notificationTriggers() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: t.components, repeats: t.repeats)
            let request = UNNotificationRequest(
                identifier: base + t.suffix,
                content: Self.content(for: reminder),
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancel(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.identifiers(for: id))
    }

    /// Every notification identifier a reminder could be holding, across all
    /// recurrence shapes, so cancelling works even after the shape changed.
    private static func identifiers(for id: UUID) -> [String] {
        let base = idPrefix + id.uuidString
        return [base]
            + (1...7).map { base + ".wd\($0)" }
            + (0..<Reminder.intervalLookahead).map { base + ".d\($0)" }
    }

    /// The notification content for a reminder. Task reminders carry the task
    /// text; focus nudges draw a line from the copy pool (fixed at scheduling
    /// time, re-rolled on every launch by `rescheduleAll`). userInfo carries the
    /// kind so NotificationRouter can route a nudge tap back into the app.
    static func content(for reminder: Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Loft Hours"
        content.body = reminder.kind == .focusNudge ? Messages.focusNudges.pick() : reminder.title
        content.sound = .default
        // Same rationale as the session cues in Notifier: reminders should
        // pierce the DND the app itself enabled (needs the entitlement on a
        // signed build; degrades to a normal banner on the ad-hoc beta).
        content.interruptionLevel = .timeSensitive
        content.userInfo = [NotificationRouter.kindKey: reminder.kind.rawValue]
        return content
    }

    // MARK: - Google Calendar mirroring (best-effort, like the block events)

    /// Non-nil only when the user connected Google AND turned calendar sync on.
    private var calendarService: CalendarService? {
        guard let auth, let config, config.calendarSyncEnabled, auth.isConnected else { return nil }
        return CalendarService(auth: auth, calendarId: config.calendarId)
    }

    /// Replace the reminder's calendar event with one matching its current
    /// schedule: delete the old event (if any), create a new one when the
    /// reminder is enabled, and store the new event id. All failures are
    /// swallowed; a calendar hiccup never breaks the reminder itself.
    private func syncCalendarEvent(for id: UUID) {
        guard let service = calendarService,
              let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        let reminder = reminders[idx]
        let oldEventId = reminder.calendarEventId
        Task {
            if let oldEventId { await service.deleteEvent(id: oldEventId) }
            var newEventId: String? = nil
            if reminder.enabled {
                newEventId = await service.createReminderEvent(reminder)
            }
            if let i = reminders.firstIndex(where: { $0.id == id }) {
                reminders[i].calendarEventId = newEventId
                persist()
            }
        }
    }

    /// Delete a removed reminder's event. Needs only a connected account, not
    /// the sync toggle, so deleting a reminder never strands its event.
    private func deleteCalendarEvent(_ eventId: String?) {
        guard let eventId, let auth, auth.isConnected else { return }
        let service = CalendarService(auth: auth, calendarId: config?.calendarId ?? "primary")
        Task { await service.deleteEvent(id: eventId) }
    }

    // MARK: - Persistence (pure helpers, covered by --selftest)

    nonisolated static func decode(_ data: Data?) -> [Reminder] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Reminder].self, from: data)) ?? []
    }

    nonisolated static func encode(_ reminders: [Reminder]) -> Data? {
        try? JSONEncoder().encode(reminders)
    }

    private func persist() {
        defaults.set(Self.encode(reminders), forKey: Self.key)
    }
}
