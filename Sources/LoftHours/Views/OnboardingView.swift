import SwiftUI

/// First-run welcome flow, two steps. Step one greets with the big wordmark and
/// offers "Continue with Google" (connects Calendar sync up front, killing the
/// sign-in-via-Settings friction) or "Continue as a guest". Step two asks
/// "What should I call you?" on both paths; the name personalizes the cycling
/// home-screen greeting and can be changed later in Settings > Environment.
/// RootView shows this whenever `config.hasOnboarded` is false; submitting a
/// non-empty name is what completes onboarding and advances to the app.
struct OnboardingView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var googleAuth: GoogleAuth

    private enum Step {
        case welcome
        case name
    }

    @State private var step: Step = .welcome
    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    /// Transient status under the Google button (cancelled / error).
    @State private var googleStatus: String? = nil
    @State private var googleBusy = false

    /// Cap the name so the greeting stays on one line; trim before checking.
    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }
    private var canContinue: Bool { !trimmedName.isEmpty }

    private func submitName() {
        guard canContinue else { return }
        config.userName = trimmedName
        config.hasOnboarded = true
    }

    private func connectGoogle() async {
        googleBusy = true
        defer { googleBusy = false }
        do {
            _ = try await googleAuth.connect()
            config.calendarConnectedEmail = googleAuth.connectedEmail
            config.calendarSyncEnabled = true
            googleStatus = nil
            withAnimation(.easeInOut(duration: 0.25)) { step = .name }
        } catch GoogleAuth.AuthError.cancelled {
            googleStatus = "Sign-in cancelled. No rush, the guest door is open too."
        } catch {
            googleStatus = "Couldn't connect: \(error.localizedDescription)"
        }
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            p.background.ignoresSafeArea()

            switch step {
            case .welcome: welcomeStep(p)
            case .name: nameStep(p)
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    // MARK: - Step one: wordmark + sign-in choice

    private func welcomeStep(_ p: Palette) -> some View {
        // Wordmark and tagline read as one unit (tight gap), then a roomier,
        // visually balanced gap before the sign-in choices.
        VStack(spacing: 26) {
            // Negative spacing eats the whitespace baked into the wordmark
            // image's bottom edge, so the tagline visually hangs off the
            // wordmark instead of floating toward the buttons.
            VStack(spacing: -24) {
                Group {
                    if let mark = AppImages.wordmark {
                        Image(nsImage: mark)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(3, contentMode: .fit)
                            .frame(width: 450, height: 150)
                            .foregroundStyle(p.foreground)
                    } else {
                        Text("Loft Hours")
                            .font(AppFont.gaegu(67))
                            .foregroundStyle(p.foreground)
                    }
                }

                Text("Welcome to the loft. Let's get you set up.")
                    .font(AppFont.nunito(15))
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await connectGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "calendar.badge.checkmark")
                        .font(AppFont.headline)
                        .foregroundStyle(p.background)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(p.accent))
                }
                .buttonStyle(.plain)
                .disabled(googleBusy)

                Text("Signing in blocks your focus time on Google Calendar automatically.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step = .name }
                } label: {
                    Text("Continue as a guest")
                        .font(AppFont.headline)
                        .foregroundStyle(p.foreground)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(p.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(googleBusy)

                if let status = googleStatus {
                    Text(status)
                        .font(AppFont.caption)
                        .foregroundStyle(p.warn)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
        }
        .padding(40)
    }

    // MARK: - Step two: name

    private func nameStep(_ p: Palette) -> some View {
        VStack(spacing: 22) {
            Text("What should I call you?")
                .font(AppFont.gaegu(40))
                .foregroundStyle(p.foreground)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Type your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(AppFont.title2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(p.foreground)
                    .focused($fieldFocused)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(p.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
                    )
                    .onSubmit(submitName)

                Button(action: submitName) {
                    Text("Continue")
                        .font(AppFont.headline)
                        .foregroundStyle(canContinue ? p.background : p.muted)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(canContinue ? p.accent : p.surface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
            }
        }
        .padding(40)
        .onAppear { fieldFocused = true }
    }
}
