import SwiftUI

/// The four wrap-up questions, then write the log.
struct WrapUpView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    /// Parallel to `planTasks`: which intake tasks the user checked off.
    @State private var checked: [Bool] = []
    @State private var otherDelivered: String = ""
    @State private var nextStep: String = ""
    @State private var energyEnd: Energy = .medium
    @State private var reflection: String = ""

    /// The intake plan to show as a checklist. Falls back to the joined goal for
    /// sessions logged before multi-task support (or resumed ones).
    private var planTasks: [String] {
        if let t = controller.session?.tasks, !t.isEmpty { return t }
        if let g = controller.session?.goal, !g.isEmpty { return [g] }
        return []
    }

    var body: some View {
        let p = theme.palette
        GeometryReader { geo in
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nice work!")
                        .font(AppFont.heading)
                        .foregroundStyle(p.foreground)
                    if let goal = controller.session?.goal {
                        Text("You sat down to: \(goal)")
                            .foregroundStyle(p.muted)
                    }
                }

                field("So, what did you actually get done?") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(planTasks.indices, id: \.self) { idx in
                            checkRow(planTasks[idx], index: idx, palette: p)
                        }
                        TextField("Other", text: $otherDelivered, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                            .padding(.top, 2)
                    }
                }

                field("What's next on your mind?") {
                    TextField("I'm planning to...", text: $nextStep, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                field("How's the energy now?") {
                    ThemedSegmented(
                        options: Energy.allCases.map { ($0, $0.label) },
                        selection: $energyEnd,
                        palette: p
                    )
                }

                field("Anything you want to jot down before you log off? (optional)") {
                    TextField("A line of reflection, or leave it blank", text: $reflection, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                }

                HStack(spacing: 12) {
                    Button {
                        let done = planTasks.indices
                            .filter { checked.indices.contains($0) && checked[$0] }
                            .map { planTasks[$0] }
                        controller.completeWrapUp(
                            completedTasks: done,
                            otherDelivered: otherDelivered.trimmingCharacters(in: .whitespacesAndNewlines),
                            nextStep: nextStep.trimmingCharacters(in: .whitespacesAndNewlines),
                            energyEnd: energyEnd,
                            reflection: reflection.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    } label: {
                        Text("Save and finish")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(p.accent)

                    Button {
                        controller.discardAndRestart()
                    } label: {
                        Text("Start another session")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .tint(p.accent)
                    .help("Skip logging this one and set up a fresh session.")
                }
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
            if checked.count != planTasks.count {
                checked = Array(repeating: false, count: planTasks.count)
            }
        }
    }

    /// One read-only task label with a toggleable checkbox in front of it. The
    /// label text mirrors what the user wrote at intake and can't be edited.
    @ViewBuilder
    private func checkRow(_ task: String, index: Int, palette p: Palette) -> some View {
        Button {
            if checked.indices.contains(index) { checked[index].toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: (checked.indices.contains(index) && checked[index]) ? "checkmark.square.fill" : "square")
                    .foregroundStyle((checked.indices.contains(index) && checked[index]) ? p.accent : p.muted)
                Text(task)
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppFont.headline).foregroundStyle(theme.palette.foreground)
            content()
        }
    }
}
