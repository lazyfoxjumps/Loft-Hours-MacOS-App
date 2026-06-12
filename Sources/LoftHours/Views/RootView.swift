import SwiftUI

/// Routes the main window to the right screen for the current phase and lays
/// the themed background under everything, with a gear button for the theme
/// panel (hidden on the final "done" screen, matching the template).
struct RootView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var googleAuth: GoogleAuth
    @EnvironmentObject private var reminderService: ReminderService

    private var isDone: Bool {
        if case .done = controller.phase { return true }
        return false
    }

    var body: some View {
        if !config.hasOnboarded {
            OnboardingView()
                .environmentObject(theme)
                .environmentObject(config)
                .environmentObject(googleAuth)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        let p = theme.palette
        return ZStack {
            (isDone ? p.doneBackground : p.background)
                .ignoresSafeArea()

            Group {
                switch controller.phase {
                case .intake:
                    IntakeView()
                case .running:
                    TimerView()
                case .breakTime:
                    BreakView()
                case .wrapUp:
                    WrapUpView()
                case .done(let logPath):
                    DoneView(logPath: logPath)
                }
            }

            if !isDone {
                gearButton(p)
            }
        }
        // The wordmark gets its own reserved strip instead of floating over the
        // content. The opaque background matters: scroll content passing the
        // strip is hidden behind it instead of bleeding through the glyphs.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerMark(p)
                .background(isDone ? p.doneBackground : p.background)
        }
        // Floor below which nothing overlaps: the gear clears the intake
        // header's Review button with room to spare at 660.
        .frame(minWidth: 660, minHeight: 660)
        .task {
            controller.requestNotificationAuthorization()
            // Re-mirror the saved reminders into the notification center each
            // launch: idempotent (stable identifiers) and it re-rolls the
            // focus-nudge copy so repeats don't go stale.
            reminderService.rescheduleAll()
        }
        .animation(.easeInOut(duration: 0.4), value: theme.selected)
        .sheet(isPresented: $controller.showSettings) {
            SettingsPanel()
                .environmentObject(theme)
                .environmentObject(config)
        }
        .sheet(isPresented: $controller.showReview) {
            ReviewView()
                .environmentObject(controller)
                .environmentObject(theme)
        }
        .sheet(isPresented: $controller.showReminders) {
            RemindersSheet()
                .environmentObject(controller)
                .environmentObject(theme)
                .environmentObject(reminderService)
        }
        // Tapping a "Your day" rail row opens that one reminder's editor
        // directly, skipping the All reminders list.
        .sheet(item: $controller.reminderToEdit) { reminder in
            ReminderEditor(
                existing: reminder,
                onSave: { updated in
                    reminderService.update(updated)
                    controller.reminderToEdit = nil
                },
                onCancel: { controller.reminderToEdit = nil }
            )
            .environmentObject(theme)
        }
    }

    /// The small "Loft Hours" wordmark in its reserved strip at the bottom of
    /// every page, in the Gaegu logo face.
    private func footerMark(_ p: Palette) -> some View {
        Group {
            if let mark = AppImages.wordmark {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 36)
                    .foregroundStyle(p.muted)
            } else {
                Text("Loft Hours")
                    .font(AppFont.footerMark)
                    .foregroundStyle(p.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
    }

    private func gearButton(_ p: Palette) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    controller.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(p.foreground)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(p.surface).overlay(Circle().stroke(p.surfaceBorder, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            Spacer()
        }
        .padding(14)
        // A touch more clearance so the gear doesn't crowd the window edge.
        .padding(.trailing, 5)
    }
}
