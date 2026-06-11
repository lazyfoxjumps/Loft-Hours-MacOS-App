import SwiftUI

/// The "All reminders" management sheet, opened from the home rail's pill (or
/// by tapping a rail row, which deep-links straight into that reminder's edit
/// form via `SessionController.reminderToEdit`). This replaces the old
/// Settings > Reminders tab so reminders live one click from where they show.
struct RemindersSheet: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var reminderService: ReminderService

    /// Whether the add/edit form is showing, and which reminder it edits
    /// (nil = creating a new one).
    @State private var showEditor = false
    @State private var editingReminder: Reminder? = nil

    /// ScrollViewReader anchor for the inline editor.
    private static let editorAnchor = "reminder-editor"

    /// Scroll the inline editor into view once it has laid out.
    private func scrollToEditor(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(Self.editorAnchor, anchor: .bottom)
            }
        }
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reminders")
                    .font(AppFont.heading)
                    .foregroundStyle(p.foreground)
                Spacer()
                Button {
                    controller.showReminders = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.muted)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Task reminders and recurring time-to-focus nudges. macOS delivers them at the right moment, even when Loft Hours is in the background.")
                            .font(AppFont.caption)
                            .foregroundStyle(p.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(reminderService.reminders) { reminder in
                            reminderRow(reminder, p)
                        }

                        if showEditor {
                            VStack(spacing: 0) {
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
                                .id(editingReminder?.id)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(p.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.surfaceBorder, lineWidth: 1))
                                )
                            }
                            .id(Self.editorAnchor)
                        } else {
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
                // The editor appears at the bottom of the list, so bring it
                // into view whenever it opens (or switches target) — otherwise
                // a long list hides it below the fold and the deep-link from
                // the home rail looks like a no-op.
                .onChange(of: showEditor) {
                    if showEditor { scrollToEditor(proxy) }
                }
                .onChange(of: editingReminder) {
                    if showEditor { scrollToEditor(proxy) }
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 480)
        .background(p.background)
        .onAppear {
            // Deep-link from a rail row: open straight into that reminder.
            if let target = controller.reminderToEdit {
                editingReminder = target
                showEditor = true
                controller.reminderToEdit = nil
            }
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
