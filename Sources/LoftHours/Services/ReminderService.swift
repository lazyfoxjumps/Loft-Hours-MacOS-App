import Foundation
import UserNotifications

/// Owns the user's reminders: persists them as one JSON blob in UserDefaults
/// and mirrors each enabled one into a scheduled local notification. One
/// UNCalendarNotificationTrigger per reminder, with the identifier derived from
/// its id, so re-scheduling the same reminder replaces instead of duplicating.
@MainActor
final class ReminderService: ObservableObject {
    @Published private(set) var reminders: [Reminder]

    private let defaults: UserDefaults
    private static let key = "lofthours.reminders"
    private static let idPrefix = "lofthours.reminder."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.reminders = Self.decode(defaults.data(forKey: Self.key))
    }

    // MARK: - CRUD

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        persist()
        schedule(reminder)
    }

    func update(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[idx] = reminder
        persist()
        cancel(reminder.id)
        schedule(reminder)
    }

    func remove(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        persist()
        cancel(id)
    }

    func setEnabled(_ on: Bool, id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].enabled = on
        persist()
        cancel(id)
        if on { schedule(reminders[idx]) }
    }

    /// Re-mirror every reminder into the notification center. Called once at
    /// launch: identifiers are stable so this replaces rather than duplicates,
    /// and it heals drift (cleared notifications, a new focus-nudge line).
    func rescheduleAll() {
        for reminder in reminders {
            cancel(reminder.id)
            schedule(reminder)
        }
    }

    // MARK: - Notification mirroring

    private func schedule(_ reminder: Reminder) {
        guard reminder.enabled else { return }
        // A one-off already in the past has nothing left to fire.
        guard reminder.nextFireDate() != nil else { return }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: reminder.triggerComponents(),
            repeats: reminder.repeats
        )
        let request = UNNotificationRequest(
            identifier: Self.idPrefix + reminder.id.uuidString,
            content: Self.content(for: reminder),
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancel(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.idPrefix + id.uuidString])
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
