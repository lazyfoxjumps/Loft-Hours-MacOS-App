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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    func notify(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The notification's left icon is the app's own bundle icon, set by the
        // system, not via UNNotificationContent. (No attachment here: an
        // attachment only ever renders as a right-side thumbnail.)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
