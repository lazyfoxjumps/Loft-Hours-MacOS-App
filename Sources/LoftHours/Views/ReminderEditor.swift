import SwiftUI
import AppKit

/// AppKit-backed stepper date field with the bezel stripped, so the editor can
/// draw its own box around it. The native bezel hugs the digits with zero side
/// padding and exposes no knob for it; SwiftUI padding only grows the outside
/// of the control. Bezel off + our own background = real left/right breathing
/// room without making the field any taller. Shared with RoutineEditor.
struct BareStepperDatePicker: NSViewRepresentable {
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
    @State private var customMode: Reminder.CustomMode
    @State private var customWeekdays: Set<Int>
    @State private var customDays: Int

    init(existing: Reminder? = nil, onSave: @escaping (Reminder) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _kind = State(initialValue: existing?.kind ?? .task)
        _title = State(initialValue: existing?.title ?? "")
        _recurrence = State(initialValue: existing?.recurrence ?? .once)
        _customMode = State(initialValue: existing?.customMode ?? .weekdays)
        _customWeekdays = State(initialValue: existing?.customWeekdays ?? [])
        _customDays = State(initialValue: existing?.customDays ?? 2)
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
        let titled = kind == .focusNudge || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let scheduled = !(recurrence == .custom && customMode == .weekdays && customWeekdays.isEmpty)
        return titled && scheduled
    }

    private var draft: Reminder {
        var r = existing ?? Reminder()
        r.kind = kind
        r.title = kind == .task ? title.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        r.recurrence = recurrence
        r.anchor = anchor
        r.customMode = customMode
        r.customWeekdays = customWeekdays
        r.customDays = customDays
        return r
    }

    /// The date picker only needs a calendar date when the date itself matters:
    /// a one-off's exact day, or the count-from day of an every-N-days schedule.
    private var pickerShowsDate: Bool {
        switch recurrence {
        case .once, .weekly, .monthly: return true
        case .daily: return false
        case .custom: return customMode == .everyNDays
        }
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
                Text("A gentle reminder from the loft when it's time to focus.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ThemedSegmented(
                options: Reminder.Recurrence.allCases.map { ($0, $0.label) },
                selection: $recurrence,
                palette: p
            )

            if recurrence == .custom {
                ThemedSegmented(
                    options: [(.weekdays, "Days of the week"), (.everyNDays, "Every few days")],
                    selection: $customMode,
                    palette: p
                )

                if customMode == .weekdays {
                    WeekdayChips(selection: $customWeekdays, palette: p)
                } else {
                    HStack(spacing: 8) {
                        Text("Every \(customDays) days")
                            .font(AppFont.callout)
                            .monospacedDigit()
                            .foregroundStyle(p.foreground)
                        Stepper("", value: $customDays, in: 2...90)
                            .labelsHidden()
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Text("When")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                    // Nunito's baseline sits a touch high next to the AppKit
                    // field; nudge so label and digits read as one line.
                    .baselineOffset(-1)
                BareStepperDatePicker(date: $anchor, showsDate: pickerShowsDate)
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
                // Same custom chrome as Cancel so the pair sit at identical
                // heights; the system .borderedProminent rendered smaller.
                Button(action: { onSave(draft) }) {
                    Text("Save")
                        .font(AppFont.callout)
                        .foregroundStyle(canSave ? p.background : p.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canSave ? p.accent : p.surface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(16)
        // A touch wider than the old 340 so five recurrence segments breathe.
        .frame(width: 380)
        .background(p.background)
    }

    /// Caption under the picker spelling out what the recurrence actually does,
    /// including the monthly 29-31 clamp flag.
    private var scheduleNote: String? {
        RecurrenceCopy.note(
            recurrence: recurrence,
            customMode: customMode,
            customWeekdays: customWeekdays,
            customDays: customDays,
            anchor: anchor
        )
    }
}

/// One toggle chip per weekday, in the user's first-day-of-week order, for the
/// custom "days of the week" schedule. Shared by the reminder and routine
/// editors.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>
    let palette: Palette

    var body: some View {
        let cal = Calendar.current
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(cal.veryShortWeekdaySymbols[weekday - 1])
                        .font(AppFont.nunito(12, on ? .semibold : .regular))
                        .foregroundStyle(on ? palette.background : palette.foreground)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(on ? palette.accent : palette.surface)
                                .overlay(Circle().stroke(palette.surfaceBorder, lineWidth: on ? 0 : 1))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(cal.weekdaySymbols[weekday - 1])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The recurrence caption both editors show under their date picker, spelling
/// out what the schedule actually does, including the monthly 29-31 clamp flag.
enum RecurrenceCopy {
    static func note(
        recurrence: Reminder.Recurrence,
        customMode: Reminder.CustomMode,
        customWeekdays: Set<Int>,
        customDays: Int,
        anchor: Date,
        calendar: Calendar = .current
    ) -> String? {
        switch recurrence {
        case .once:
            return nil
        case .daily:
            return "Repeats every day at this time."
        case .weekly:
            let fmt = DateFormatter()
            let name = fmt.weekdaySymbols[calendar.component(.weekday, from: anchor) - 1]
            return "Repeats every \(name) at this time."
        case .monthly:
            let day = calendar.component(.day, from: anchor)
            if day > Reminder.monthlyDayCap {
                return "Day \(day) doesn't exist in every month, so this fires on the 28th instead, every month without fail."
            }
            return "Repeats on day \(day) of every month."
        case .custom:
            switch customMode {
            case .weekdays:
                if customWeekdays.isEmpty {
                    return "Pick at least one day above."
                }
                if customWeekdays.count == 7 {
                    return "Repeats every day at this time."
                }
                let fmt = DateFormatter()
                let names = customWeekdays.sorted().map { fmt.shortWeekdaySymbols[$0 - 1] }
                return "Repeats every \(names.joined(separator: ", ")) at this time."
            case .everyNDays:
                return "Repeats every \(customDays) days at this time, counting from the date above."
            }
        }
    }
}
