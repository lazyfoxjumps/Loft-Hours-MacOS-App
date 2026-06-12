import Foundation
import UserNotifications

/// Owns the user's routines: persists them as one JSON blob in UserDefaults
/// and mirrors each enabled one into scheduled local notifications (the gentle
/// "window just opened" nudge, per-routine opt-out via `notify`). Identifiers
/// derive from the routine id, so re-scheduling replaces instead of
/// duplicating. When Google Calendar sync is on, each routine is also mirrored
/// to a recurring calendar event spanning its window, always Free, never Busy.
@MainActor
final class RoutineService: ObservableObject {
    @Published private(set) var routines: [Routine]

    private let defaults: UserDefaults
    private let auth: GoogleAuth?
    private let config: ConfigStore?
    private static let key = "lofthours.routines"
    private static let idPrefix = "lofthours.routine."
    /// userInfo value for `NotificationRouter.kindKey` on routine nudges.
    /// Unknown kinds just dismiss in the router today; tap routing comes with
    /// the runner phase.
    static let notificationKind = "routine"

    init(defaults: UserDefaults = .standard, auth: GoogleAuth? = nil, config: ConfigStore? = nil) {
        self.defaults = defaults
        self.auth = auth
        self.config = config
        self.routines = Self.decode(defaults.data(forKey: Self.key))
    }

    // MARK: - CRUD

    func add(_ routine: Routine) {
        routines.append(routine)
        persist()
        schedule(routine)
        syncCalendarEvent(for: routine.id)
    }

    func update(_ routine: Routine) {
        guard let idx = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        var updated = routine
        updated.calendarEventId = updated.calendarEventId ?? routines[idx].calendarEventId
        routines[idx] = updated
        persist()
        cancel(routine.id)
        schedule(updated)
        syncCalendarEvent(for: routine.id)
    }

    func remove(_ id: UUID) {
        let eventId = routines.first(where: { $0.id == id })?.calendarEventId
        routines.removeAll { $0.id == id }
        persist()
        cancel(id)
        deleteCalendarEvent(eventId)
    }

    func setEnabled(_ on: Bool, id: UUID) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[idx].enabled = on
        persist()
        cancel(id)
        if on { schedule(routines[idx]) }
        syncCalendarEvent(for: id)
    }

    /// Re-mirror every routine into the notification center. Called once at
    /// launch, like ReminderService: stable identifiers replace rather than
    /// duplicate, the nudge copy gets re-rolled, and the every-N-days rolling
    /// window refills. Calendar events are left alone (already there).
    func rescheduleAll() {
        for routine in routines {
            cancel(routine.id)
            schedule(routine)
        }
    }

    // MARK: - Notification mirroring

    private func schedule(_ routine: Routine) {
        guard routine.enabled, routine.notify else { return }
        guard routine.nextFireDate() != nil else { return }
        let base = Self.idPrefix + routine.id.uuidString
        for t in routine.notificationTriggers() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: t.components, repeats: t.repeats)
            let request = UNNotificationRequest(
                identifier: base + t.suffix,
                content: Self.content(for: routine),
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancel(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.identifiers(for: id))
    }

    /// Every notification identifier a routine could be holding, across all
    /// recurrence shapes, so cancelling works even after the shape changed.
    private static func identifiers(for id: UUID) -> [String] {
        let base = idPrefix + id.uuidString
        return [base]
            + (1...7).map { base + ".wd\($0)" }
            + (0..<Reminder.intervalLookahead).map { base + ".d\($0)" }
    }

    /// The nudge content: the routine's own name (with emoji) as the title, a
    /// fresh line from the copy pool as the body (fixed at scheduling time,
    /// re-rolled on every launch by `rescheduleAll`).
    static func content(for routine: Routine) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = routine.displayName.isEmpty ? "Loft Hours" : routine.displayName
        content.body = Messages.routineNudges.pick()
        content.sound = .default
        // Same rationale as reminders: pierce the DND the app itself enabled
        // (signed-build entitlement; degrades to a normal banner on ad-hoc).
        content.interruptionLevel = .timeSensitive
        content.userInfo = [NotificationRouter.kindKey: Self.notificationKind]
        return content
    }

    // MARK: - Google Calendar mirroring (best-effort, like reminders)

    private var calendarService: CalendarService? {
        guard let auth, let config, config.calendarSyncEnabled, auth.isConnected else { return nil }
        return CalendarService(auth: auth, calendarId: config.calendarId)
    }

    /// Replace the routine's calendar event with one matching its current
    /// schedule: delete the old event (if any), create a new one when the
    /// routine is enabled, and store the new event id. All failures are
    /// swallowed; a calendar hiccup never breaks the routine itself.
    private func syncCalendarEvent(for id: UUID) {
        guard let service = calendarService,
              let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        let routine = routines[idx]
        let oldEventId = routine.calendarEventId
        Task {
            if let oldEventId { await service.deleteEvent(id: oldEventId) }
            var newEventId: String? = nil
            if routine.enabled {
                newEventId = await service.createRoutineEvent(routine)
            }
            if let i = routines.firstIndex(where: { $0.id == id }) {
                routines[i].calendarEventId = newEventId
                persist()
            }
        }
    }

    /// Delete a removed routine's event. Needs only a connected account, not
    /// the sync toggle, so deleting a routine never strands its event.
    private func deleteCalendarEvent(_ eventId: String?) {
        guard let eventId, let auth, auth.isConnected else { return }
        let service = CalendarService(auth: auth, calendarId: config?.calendarId ?? "primary")
        Task { await service.deleteEvent(id: eventId) }
    }

    // MARK: - Persistence (pure helpers, covered by --selftest)

    nonisolated static func decode(_ data: Data?) -> [Routine] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Routine].self, from: data)) ?? []
    }

    nonisolated static func encode(_ routines: [Routine]) -> Data? {
        try? JSONEncoder().encode(routines)
    }

    private func persist() {
        defaults.set(Self.encode(routines), forKey: Self.key)
    }
}
