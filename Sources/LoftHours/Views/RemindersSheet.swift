import SwiftUI

/// The "All reminders" management sheet, opened from the home rail's pill.
/// Editing never happens inline: the pencil (or Add reminder) opens the editor
/// in its own sheet on top, so nobody scrolls a long list to find the form.
/// (Tapping a rail row on the home screen skips this sheet entirely and opens
/// the editor directly via `SessionController.reminderToEdit`.)
struct RemindersSheet: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var reminderService: ReminderService

    /// Whether the editor sheet is up, and which reminder it edits
    /// (nil = creating a new one).
    @State private var showEditor = false
    @State private var editingReminder: Reminder? = nil

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reminders")
                    .font(AppFont.heading)
                    .foregroundStyle(p.foreground)
                Spacer()
                SheetCloseButton(palette: p) {
                    controller.showReminders = false
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Task reminders and recurring time-to-focus nudges. macOS delivers them at the right moment, even when Loft Hours is in the background.")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(reminderService.reminders) { reminder in
                        reminderRow(reminder, p)
                    }

                    Button {
                        editingReminder = nil
                        showEditor = true
                    } label: {
                        Label("Add reminder", systemImage: "plus")
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
            ReminderEditor(
                existing: editingReminder,
                onSave: { reminder in
                    if editingReminder == nil {
                        reminderService.add(reminder)
                    } else {
                        reminderService.update(reminder)
                    }
                    showEditor = false
                    editingReminder = nil
                },
                onCancel: {
                    showEditor = false
                    editingReminder = nil
                }
            )
            .environmentObject(theme)
        }
    }

    private func reminderRow(_ reminder: Reminder, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: reminder.kind == .focusNudge ? "timer" : "bell")
                .foregroundStyle(reminder.enabled ? p.accent : p.muted)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.displayTitle)
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                    .lineLimit(1)
                Text(reminder.scheduleDescription())
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { reminder.enabled },
                set: { reminderService.setEnabled($0, id: reminder.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(p.accent)
            .labelsHidden()

            Button {
                editingReminder = reminder
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(p.muted)
            }
            .buttonStyle(.plain)
            .help("Edit this reminder")

            Button {
                reminderService.remove(reminder.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(p.muted)
            }
            .buttonStyle(.plain)
            .help("Delete this reminder")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.surfaceBorder, lineWidth: 1))
        )
        .opacity(reminder.enabled ? 1 : 0.6)
    }
}

/// The shared close button for the app's sheets: a generously sized X with a
/// real hit target, so it stays easy to spot and click for everyone (the old
/// bare 13pt glyph was too small for impaired vision).
struct SheetCloseButton: View {
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.foreground)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(palette.surface)
                        .overlay(Circle().stroke(palette.surfaceBorder, lineWidth: 1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}
