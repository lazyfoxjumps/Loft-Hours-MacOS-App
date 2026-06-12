import SwiftUI

/// The routines management sheet, opened from the home rail's "Routines" pill.
/// Same shape as RemindersSheet: a list of rows with enable toggles, and the
/// editor always opens in its own sheet on top, never inline. (Tapping a rail
/// row on the home screen skips this sheet and opens the editor directly via
/// `SessionController.routineToEdit`.)
struct RoutinesSheet: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var routineService: RoutineService

    /// Whether the editor sheet is up, and which routine it edits
    /// (nil = creating a new one).
    @State private var showEditor = false
    @State private var editingRoutine: Routine? = nil

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Routines")
                    .font(AppFont.heading)
                    .foregroundStyle(p.foreground)
                Spacer()
                SheetCloseButton(palette: p) {
                    controller.showRoutines = false
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recurring time blocks with their own checklist, like a morning or wind-down routine. Start one with a click when its window opens and tick through the steps.")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(routineService.routines) { routine in
                        routineRow(routine, p)
                    }

                    Button {
                        editingRoutine = nil
                        showEditor = true
                    } label: {
                        Label("Add routine", systemImage: "plus")
                            .font(AppFont.caption)
                            .foregroundStyle(p.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 480)
        .background(p.background)
        .sheet(isPresented: $showEditor) {
            RoutineEditor(
                existing: editingRoutine,
                onSave: { routine in
                    if editingRoutine == nil {
                        routineService.add(routine)
                    } else {
                        routineService.update(routine)
                    }
                    showEditor = false
                    editingRoutine = nil
                },
                onCancel: {
                    showEditor = false
                    editingRoutine = nil
                }
            )
            .environmentObject(theme)
        }
    }

    private func routineRow(_ routine: Routine, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Text(routine.emoji.isEmpty ? "✦" : routine.emoji)
                .font(.system(size: 14))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                    .lineLimit(1)
                Text(scheduleLine(routine))
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { routine.enabled },
                set: { routineService.setEnabled($0, id: routine.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(p.accent)
            .labelsHidden()

            Button {
                editingRoutine = routine
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(p.muted)
            }
            .buttonStyle(.plain)
            .help("Edit this routine")

            Button {
                routineService.remove(routine.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(p.muted)
            }
            .buttonStyle(.plain)
            .help("Delete this routine")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.surfaceBorder, lineWidth: 1))
        )
        .opacity(routine.enabled ? 1 : 0.6)
    }

    /// "Daily at 7:00 AM, 45 min · 6 tasks"
    private func scheduleLine(_ routine: Routine) -> String {
        let base = routine.scheduleDescription()
        guard !routine.tasks.isEmpty else { return base }
        let unit = routine.tasks.count == 1 ? "task" : "tasks"
        return "\(base) · \(routine.tasks.count) \(unit)"
    }
}
