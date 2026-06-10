import SwiftUI

/// Routes the main window to the right screen for the current phase and lays
/// the themed background under everything, with a gear button for the theme
/// panel (hidden on the final "done" screen, matching the template).
struct RootView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var googleAuth: GoogleAuth

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

            footerMark(p)
        }
        .frame(minWidth: 460, minHeight: 560)
        .task { controller.requestNotificationAuthorization() }
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
    }

    /// The small "Loft Hours" wordmark pinned to the bottom-center of every
    /// page, in the Gaegu logo face.
    private func footerMark(_ p: Palette) -> some View {
        VStack {
            Spacer()
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
            .padding(.bottom, 12)
        }
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
    }
}
