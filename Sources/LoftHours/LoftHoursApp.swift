import SwiftUI

struct LoftHoursApp: App {
    @StateObject private var config: ConfigStore
    @StateObject private var theme = ThemeStore()
    @StateObject private var controller: SessionController
    @StateObject private var googleAuth: GoogleAuth
    @StateObject private var reminderService: ReminderService
    @StateObject private var routineService: RoutineService
    @StateObject private var routineTracker: RoutineTracker
    @StateObject private var routineRunner: RoutineRunner

    init() {
        let cfg = ConfigStore()
        let auth = GoogleAuth()
        _config = StateObject(wrappedValue: cfg)
        _googleAuth = StateObject(wrappedValue: auth)
        _controller = StateObject(wrappedValue: SessionController(config: cfg, auth: auth))
        // Reminders mirror into Google Calendar when sync is on, so the
        // service needs the same auth + config the session path uses.
        _reminderService = StateObject(wrappedValue: ReminderService(auth: auth, config: cfg))
        // Routines mirror to Google Calendar too (as Free slots), so the same
        // auth + config go in.
        _routineService = StateObject(wrappedValue: RoutineService(auth: auth, config: cfg))
        // The runner writes routine ticks/finishes through the tracker, so it
        // shares the one tracker instance the rest of the app reads from.
        let tracker = RoutineTracker()
        _routineTracker = StateObject(wrappedValue: tracker)
        _routineRunner = StateObject(wrappedValue: RoutineRunner(tracker: tracker))
        // Claim the notification-center delegate so reminder taps route back
        // into the app and reminders still banner while we're frontmost.
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup("Loft Hours", id: "main") {
            RootView()
                .environmentObject(controller)
                .environmentObject(theme)
                .environmentObject(config)
                .environmentObject(googleAuth)
                .environmentObject(reminderService)
                .environmentObject(routineService)
                .environmentObject(routineTracker)
                .environmentObject(routineRunner)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(controller)
        } label: {
            if let icon = AppImages.menuBar {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "timer")
            }
        }
    }
}
