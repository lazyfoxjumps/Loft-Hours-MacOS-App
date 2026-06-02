import Foundation
import UserNotifications

/// Native OS notifications for the focus cues. Fired immediately (nil trigger)
/// from the controller's tick at the moment each threshold is crossed, so they
/// stay in sync with pause/rewind/skip instead of drifting like wall-clock
/// scheduled bells.
@MainActor
final class Notifier {
    private var authorized = false

    func requestAuthorization() {
        // On by default: ask on first launch (RootView calls this on appear).
        // Breaking through Focus/DND is driven by the time-sensitive *entitlement*
        // plus content.interruptionLevel below, not an authorization option
        // (the .timeSensitive option was deprecated in macOS 12).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    func notify(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Mark our cues time-sensitive so they pierce the Focus/DND we asked the
        // system to enable for this session. Without this, our own DND would
        // mute the very nudges the user relies on. (Time-sensitive needs the
        // matching entitlement on a signed build; on the unsigned ad-hoc beta it
        // degrades gracefully to a normal banner, which is fine.)
        content.interruptionLevel = .timeSensitive
        // The notification's left icon is the app's own bundle icon, set by the
        // system, not via UNNotificationContent. (No attachment here: an
        // attachment only ever renders as a right-side thumbnail.)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
