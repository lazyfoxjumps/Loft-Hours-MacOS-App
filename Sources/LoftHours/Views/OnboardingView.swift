import SwiftUI

/// First-run screen: a plain themed page that asks the user's name once. The
/// name personalizes the cycling home-screen greeting and can be changed later
/// in Settings > Environment. RootView shows this whenever `config.userName` is
/// empty, so completing it (a non-empty name) is what advances to the app.
struct OnboardingView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore

    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    /// Cap the name so the greeting stays on one line; trim before checking.
    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }
    private var canContinue: Bool { !trimmedName.isEmpty }

    private func submit() {
        guard canContinue else { return }
        config.userName = trimmedName
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            p.background.ignoresSafeArea()

            VStack(spacing: 22) {
                Text("What's your name?")
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
                        .onSubmit(submit)

                    Button(action: submit) {
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
        }
        .frame(minWidth: 460, minHeight: 560)
        .onAppear { fieldFocused = true }
    }
}
