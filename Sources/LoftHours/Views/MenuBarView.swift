import SwiftUI

/// The menu-bar dropdown. Phase 1 keeps it minimal: status line plus quit.
/// The richer menu-bar timer lands alongside notifications in Phase 2.
struct MenuBarView: View {
    @EnvironmentObject private var controller: SessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch controller.phase {
        case .intake:
            Text("Nothing going right now")
        case .running:
            Text(controller.isPaused ? "Paused" : "Focusing")
            // Note: the menu-bar dropdown is a native AppKit menu, which renders
            // items in the system menu font regardless of SwiftUI font modifiers.
            // That's system chrome, same category as SF Symbols: left alone.
            if let goal = controller.session?.goal {
                Text(goal).font(AppFont.caption)
            }
            Divider()
            if !controller.isStopwatch {
                Button {
                    controller.rewind()
                } label: {
                    Label("Rewind block", systemImage: "backward.end.fill")
                }
            }
            Button {
                controller.togglePause()
            } label: {
                Label(controller.isPaused ? "Resume" : "Pause",
                      systemImage: controller.isPaused ? "play.fill" : "pause.fill")
            }
            Button {
                controller.finishBlock()
            } label: {
                controller.isStopwatch
                    ? Label("Stop the clock", systemImage: "stop.fill")
                    : Label("Complete block", systemImage: "forward.end.fill")
            }
        case .breakTime:
            Text(controller.isBreakOver ? "Break's over" : "On a break")
        case .wrapUp:
            Text("Wrapping up...")
        case .done:
            Text("All logged")
        }

        Divider()
        Button("Review this week") { openReview(.week) }
        Button("Review this month") { openReview(.month) }

        Divider()
        Button("Quit Loft Hours") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Reopen/focus the main window, bring the app forward, then open the
    /// Review sheet on it. `openWindow` re-shows the window even if the user
    /// had closed it; `bringToFront` un-minimizes and activates.
    private func openReview(_ scope: ReviewScope) {
        openWindow(id: "main")
        AppActivator.bringToFront()
        controller.openReview(scope)
    }
}
