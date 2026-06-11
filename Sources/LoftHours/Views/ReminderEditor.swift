import SwiftUI
import AppKit

/// AppKit-backed stepper date field with the bezel stripped, so the editor can
/// draw its own box around it. The native bezel hugs the digits with zero side
/// padding and exposes no knob for it; SwiftUI padding only grows the outside
/// of the control. Bezel off + our own background = real left/right breathing
/// room without making the field any taller.
private struct BareStepperDatePicker: NSViewRepresentable {
    @Binding var date: Date
    var showsDate: Bool

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.font = NSFont(name: "Nunito", size: 12) ?? .systemFont(ofSize: 12)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        picker.datePickerElements = showsDate ? [.yearMonthDay, .hourMinute] : [.hourMinute]
        if picker.dateValue != date { picker.dateValue = date }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: BareStepperDatePicker
        init(_ parent: BareStepperDatePicker) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}

/// The add/edit form for a reminder, shared by the home screen's quick-add
/// popover and the Settings > Reminders tab. Kind toggle (task vs "time to
/// focus" nudge), title for tasks, recurrence, and a date/time picker whose
/// visible parts adapt to the recurrence (a daily reminder only needs a time;
/// weekly and monthly read their weekday/day from the picked date).
struct ReminderEditor: View {
    @EnvironmentObject private var theme: ThemeStore

    let existing: Reminder?
    let onSave: (Reminder) -> Void
    let onCancel: () -> Void

    @State private var kind: Reminder.Kind
    @State private var title: String
    @State private var recurrence: Reminder.Recurrence
    @State private var anchor: Date

    init(existing: Reminder? = nil, onSave: @escaping (Reminder) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _kind = State(initialValue: existing?.kind ?? .task)
        _title = State(initialValue: existing?.title ?? "")
        _recurrence = State(initialValue: existing?.recurrence ?? .once)
        // New reminders default to the top of the next hour, a likelier intent
        // than "this exact second".
        let defaultAnchor = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date()
        _anchor = State(initialValue: existing?.anchor ?? defaultAnchor)
    }

    private var canSave: Bool {
        kind == .focusNudge || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draft: Reminder {
        var r = existing ?? Reminder()
        r.kind = kind
        r.title = kind == .task ? title.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        r.recurrence = recurrence
        r.anchor = anchor
        return r
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "New reminder" : "Edit reminder")
                .font(AppFont.headline)
                .foregroundStyle(p.foreground)

            ThemedSegmented(
                options: [(.task, "Task"), (.focusNudge, "Time to focus")],
                selection: $kind,
                palette: p
            )

            if kind == .task {
                TextField("Remind me to...", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.body)
            } else {
                Text("A gentle ping to come do a focus block. The wording cycles so it stays fresh.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ThemedSegmented(
                options: Reminder.Recurrence.allCases.map { ($0, $0.label) },
                selection: $recurrence,
                palette: p
            )

            HStack(spacing: 8) {
                Text("When")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                BareStepperDatePicker(date: $anchor, showsDate: recurrence != .daily)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.surfaceBorder, lineWidth: 1))
                    )
            }
            .frame(maxWidth: .infinity)

            if let note = scheduleNote {
                Text(note)
                    .font(AppFont.caption)
                    .foregroundStyle(draft.monthlyDayClamped() ? p.warn : p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                // Outlined in the palette's foreground so it reads on every
                // theme: light-on-dark palettes get a light button, dark-on-light
                // get a dark one. The system .bordered style ignored the theme
                // and went dark-on-dark.
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppFont.callout)
                        .foregroundStyle(p.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(p.foreground.opacity(0.55), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Button("Save") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .tint(p.accent)
                    .controlSize(.small)
                    .font(AppFont.callout)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(p.background)
    }

    /// Caption under the picker spelling out what the recurrence actually does,
    /// including the monthly 29-31 clamp flag.
    private var scheduleNote: String? {
        let cal = Calendar.current
        switch recurrence {
        case .once:
            return nil
        case .daily:
            return "Repeats every day at this time."
        case .weekly:
            let fmt = DateFormatter()
            let name = fmt.weekdaySymbols[cal.component(.weekday, from: anchor) - 1]
            return "Repeats every \(name) at this time."
        case .monthly:
            let day = cal.component(.day, from: anchor)
            if day > Reminder.monthlyDayCap {
                return "Day \(day) doesn't exist in every month, so this fires on the 28th instead, every month without fail."
            }
            return "Repeats on day \(day) of every month."
        }
    }
}
