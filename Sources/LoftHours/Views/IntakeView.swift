import SwiftUI

/// The four-question intake: goal, length, what does done look like, energy.
struct IntakeView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    @State private var tasks: [String] = [""]
    @State private var deliverable: String = ""
    @State private var energy: Energy = .medium
    @State private var durationChoice: DurationChoice = .m25
    @State private var customMinutes: String = "30"
    @FocusState private var goalFocused: Bool
    /// True once the goal field was prefilled from the previous session's next step.
    @State private var resumed: Bool = false

    enum DurationChoice: Hashable {
        case m25, m50, m90, custom
        var minutes: Int? {
            switch self {
            case .m25: return 25
            case .m50: return 50
            case .m90: return 90
            case .custom: return nil
            }
        }
        var label: String {
            switch self {
            case .m25: return "25 min"
            case .m50: return "50 min"
            case .m90: return "90 min"
            case .custom: return "Custom"
            }
        }
    }

    private var resolvedMinutes: Int? {
        if let m = durationChoice.minutes { return m }
        guard let m = Int(customMinutes.trimmingCharacters(in: .whitespaces)), m > 0 else { return nil }
        return m
    }

    /// The non-empty, trimmed tasks the user has entered.
    private var cleanTasks: [String] {
        tasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canStart: Bool {
        !cleanTasks.isEmpty && resolvedMinutes != nil
    }

    private func start() {
        guard canStart, let minutes = resolvedMinutes else { return }
        controller.startSession(
            tasks: cleanTasks,
            durationMin: minutes,
            deliverable: deliverable.trimmingCharacters(in: .whitespacesAndNewlines),
            energy: energy
        )
    }

    var body: some View {
        let p = theme.palette
        GeometryReader { geo in
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loft Hours")
                            .font(AppFont.wordmark)
                            .foregroundStyle(p.foreground)
                        Text("Let's set up a focus session.")
                            .foregroundStyle(p.muted)
                    }
                    Spacer()
                    Button {
                        controller.openReview(.week)
                    } label: {
                        Label("Review", systemImage: "chart.bar.fill")
                            .font(AppFont.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(p.accent)
                    .help("See your weekly and monthly focus rollups.")
                }

                dndToggle(p)

                field("Hey, what are you working on today?") {
                    VStack(alignment: .leading, spacing: 6) {
                        if resumed {
                            Text("Picking up from where you left off.")
                                .font(AppFont.caption)
                                .foregroundStyle(p.muted)
                        }
                        ForEach(tasks.indices, id: \.self) { idx in
                            HStack(spacing: 6) {
                                TextField(
                                    idx == 0 ? "Today, I'm working on..." : "And also...",
                                    text: Binding(
                                        get: { tasks[idx] },
                                        set: { tasks[idx] = $0 }
                                    ),
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...3)
                                .focusedIf(idx == 0, $goalFocused)
                                .onChange(of: goalFocused) { if goalFocused { resumed = false } }

                                if idx == tasks.count - 1 {
                                    Button {
                                        tasks.append("")
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(p.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Add another task")
                                } else {
                                    Button {
                                        tasks.remove(at: idx)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(p.muted)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this task")
                                }
                            }
                        }
                    }
                }

                field("How long do you want this to be?") {
                    VStack(alignment: .leading, spacing: 8) {
                        ThemedSegmented(
                            options: [(.m25, "25 min"), (.m50, "50 min"), (.m90, "90 min"), (.custom, "Custom")],
                            selection: $durationChoice,
                            palette: p
                        )

                        if durationChoice == .custom {
                            HStack(spacing: 6) {
                                TextField("30", text: $customMinutes)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                Text("minutes")
                                    .foregroundStyle(p.muted)
                            }
                        }
                    }
                }

                field("And what does done look like for this session?") {
                    TextField("One concrete thing that'll feel finished", text: $deliverable, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                field("How's your energy right now?") {
                    ThemedSegmented(
                        options: Energy.allCases.map { ($0, $0.label) },
                        selection: $energy,
                        palette: p
                    )
                }

                Button(action: start) {
                    Text("Start session")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(p.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
                .padding(.top, 4)
                }
                .frame(maxWidth: 460)
                .padding(28)
                Spacer(minLength: 0)
            }
            .frame(minHeight: geo.size.height)
        }
        }
        .onAppear {
            if cleanTasks.isEmpty, let suggestion = controller.resumeSuggestion {
                tasks = [suggestion]
                resumed = true
            }
        }
    }

    private func dndToggle(_ p: Palette) -> some View {
        Toggle(isOn: Binding(
            get: { controller.manualDNDOn },
            set: { controller.setManualDND($0) }
        )) {
            HStack(spacing: 8) {
                Image(systemName: controller.manualDNDOn ? "moon.fill" : "moon")
                    .foregroundStyle(controller.manualDNDOn ? p.accent : p.muted)
                Text("Do Not Disturb")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
            }
        }
        .toggleStyle(.switch)
        .tint(p.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
        )
        .help("Runs your configured Focus Shortcut. Set the shortcut names in Settings.")
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppFont.headline).foregroundStyle(theme.palette.foreground)
            content()
        }
    }
}

private extension View {
    /// Applies `.focused` only when `condition` is true, so a single FocusState
    /// can drive just the first field in a repeated list.
    @ViewBuilder
    func focusedIf(_ condition: Bool, _ binding: FocusState<Bool>.Binding) -> some View {
        if condition { self.focused(binding) } else { self }
    }
}
