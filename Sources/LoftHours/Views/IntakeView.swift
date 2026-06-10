import SwiftUI

/// The four-question intake: goal, length, what does done look like, energy.
struct IntakeView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore

    /// Whether the configured Focus shortcuts are present in the user's library.
    /// nil = we couldn't check (e.g. the Shortcuts CLI isn't reachable), so we
    /// stay quiet rather than nag with a false alarm.
    @State private var shortcutsInstalled: Bool? = nil

    @State private var tasks: [String] = [""]
    @State private var deliverable: String = ""
    @State private var energy: Energy = .medium
    @State private var durationChoice: DurationChoice = .m25
    @State private var customMinutes: String = "30"
    /// Stopwatch mode: no planned length, the clock just counts up until stopped.
    @State private var stopwatchMode: Bool = false
    @FocusState private var goalFocused: Bool
    /// True once the goal field was prefilled from the previous session's next step.
    @State private var resumed: Bool = false
    /// The cycling, name-personalized greeting shown in place of "Loft Hours".
    /// Computed once when the home screen appears so it stays stable while here.
    @State private var welcomeText: String = ""

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
        !cleanTasks.isEmpty && (stopwatchMode || resolvedMinutes != nil)
    }

    private func start() {
        guard canStart else { return }
        controller.startSession(
            tasks: cleanTasks,
            durationMin: stopwatchMode ? 0 : (resolvedMinutes ?? 0),
            deliverable: deliverable.trimmingCharacters(in: .whitespacesAndNewlines),
            energy: energy,
            isStopwatch: stopwatchMode
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
                        Text(welcomeText.isEmpty ? "Loft Hours" : welcomeText)
                            .font(AppFont.wordmark)
                            .foregroundStyle(p.foreground)
                        Text("Welcome to the loft. Let's get you set up.")
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

                if shortcutsInstalled == false {
                    shortcutBanner(p)
                }

                dndToggle(p)

                YourDayTimeline()

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

                field("How long are we going for?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
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
                        .disabled(stopwatchMode)
                        .opacity(stopwatchMode ? 0.45 : 1)

                        Toggle(isOn: $stopwatchMode) {
                            HStack(spacing: 8) {
                                Image(systemName: "stopwatch")
                                    .foregroundStyle(stopwatchMode ? p.accent : p.muted)
                                Text("Just track time (stopwatch)")
                                    .font(AppFont.callout)
                                    .foregroundStyle(p.foreground)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(p.accent)
                        .help("No set length. The clock counts up until you stop it, and the real time goes in your log.")
                    }
                }

                field("What would make this feel done?") {
                    TextField("One thing that'll feel good to finish", text: $deliverable, axis: .vertical)
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
                    Text("Let's get into it")
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
            refreshShortcutStatus()
            refreshWelcome()
        }
        // Re-check when the user comes back from Settings (where they'd install).
        .onChange(of: controller.showSettings) {
            if !controller.showSettings { refreshShortcutStatus() }
        }
        // Refresh the greeting immediately if the name is changed in Settings.
        .onChange(of: config.userName) { refreshWelcome() }
    }

    /// Pick a fresh, name-personalized greeting, avoiding an immediate repeat of
    /// the last one shown. Stores the chosen template so the next open differs.
    private func refreshWelcome() {
        let result = Messages.welcome(
            name: config.userName,
            date: Date(),
            avoiding: config.lastWelcomeTemplate.isEmpty ? nil : config.lastWelcomeTemplate
        )
        welcomeText = result.text
        config.lastWelcomeTemplate = result.template
    }

    /// Look up whether both configured Focus shortcuts exist. Leaves the banner
    /// hidden if we can't tell (CLI unreachable).
    private func refreshShortcutStatus() {
        guard let installed = FocusService.installedShortcutNames() else {
            shortcutsInstalled = nil
            return
        }
        shortcutsInstalled = installed.contains(config.focusShortcutOn)
            && installed.contains(config.focusShortcutOff)
    }

    /// Shown above the DND toggle when the Focus shortcuts aren't installed yet,
    /// since without them the toggle can't actually flip Do Not Disturb. Tapping
    /// it opens Settings, where the one-tap installer lives.
    private func shortcutBanner(_ p: Palette) -> some View {
        Button {
            controller.showSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(p.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick thing before you start")
                        .font(AppFont.callout)
                        .foregroundStyle(p.foreground)
                    Text("Your Do Not Disturb shortcut isn't set up yet, so the toggle below won't do much. Tap to install it in Settings, takes two seconds.")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(p.warn.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.warn.opacity(0.35), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .help("Flips on Do Not Disturb so the world leaves you alone. Set it up in Settings.")
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
