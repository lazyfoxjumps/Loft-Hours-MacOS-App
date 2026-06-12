import AppKit
import UserNotifications

/// Routes taps on the app's local notifications. Installed as the shared
/// UNUserNotificationCenter delegate at launch; nothing else claims the
/// delegate (Notifier only posts), so there's no existing one to stomp.
/// Tapping a "time to focus" nudge brings the app and its main window to the
/// front so the user lands ready to start a block; task reminders are
/// informational and just dismiss.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    /// userInfo key carrying `Reminder.Kind.rawValue` on reminder notifications.
    static let kindKey = "lofthours.reminder.kind"

    /// Claim the notification-center delegate. Call once at app startup.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show reminders as banners even while the app is frontmost; without a
    /// delegate the system silently swallows foreground notifications.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = response.notification.request.content.userInfo[Self.kindKey] as? String
        // Focus nudges and routine nudges both pull the app forward so the user
        // lands on the home screen ready to start: the routine's window is open
        // when its nudge fires, so its one-click Start CTA is already showing.
        // Task reminders are informational and just dismiss.
        if kind == Reminder.Kind.focusNudge.rawValue || kind == RoutineService.notificationKind {
            Task { @MainActor in AppActivator.bringToFront() }
        }
        completionHandler()
    }
}
