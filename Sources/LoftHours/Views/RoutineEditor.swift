import SwiftUI

/// The add/edit form for a routine, opened from the Routines sheet and from
/// the home rail's routine rows. Name + optional emoji, the full recurrence
/// option set (shared with ReminderEditor), a start time, the window length,
/// the repeating task checklist, and the notify opt-out.
struct RoutineEditor: View {
    @EnvironmentObject private var theme: ThemeStore

    let existing: Routine?
    let onSave: (Routine) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var anchor: Date
    @State private var durationMin: Int
    @State private var recurrence: Reminder.Recurrence
    @State private var customMode: Reminder.CustomMode
    @State private var customWeekdays: Set<Int>
    @State private var customDays: Int
    @State private var tasks: [RoutineTask]
    @State private var notify: Bool
    /// A transient extra circle for an emoji picked from the system palette that
    /// isn't one of the curated quick-picks. Lives only for this routine: the
    /// "+" button stays a "+", and this never joins the curated row for new
    /// routines.
    @State private var customEmoji: String
    /// Capture slot the title's "+" picker writes into; lifted into
    /// customEmoji + selection, then cleared so the "+" stays a "+".
    @State private var titlePickerBuffer = ""

    /// A quick-pick row of routine-flavored emoji so most people never have to
    /// open the system picker. Tapping the selected one clears it.
    private static let curatedEmoji = ["☀️", "🌙", "🧘", "🏃", "🛏️", "☕️", "📚", "🧹", "💊"]

    init(existing: Routine? = nil, onSave: @escaping (Routine) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "")
        _durationMin = State(initialValue: existing?.durationMin ?? 30)
        _recurrence = State(initialValue: existing?.recurrence ?? .daily)
        _customMode = State(initialValue: existing?.customMode ?? .weekdays)
        _customWeekdays = State(initialValue: existing?.customWeekdays ?? [])
        _customDays = State(initialValue: existing?.customDays ?? 2)
        _tasks = State(initialValue: existing?.tasks ?? [])
        _notify = State(initialValue: existing?.notify ?? true)
        // If an existing routine's emoji isn't a curated quick-pick, surface it
        // as the transient custom circle (selected) so it stays editable.
        let savedEmoji = existing?.emoji ?? ""
        _customEmoji = State(initialValue: (!savedEmoji.isEmpty && !Self.curatedEmoji.contains(savedEmoji)) ? savedEmoji : "")
        // New routines default to the top of the next hour, same as reminders.
        let defaultAnchor = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date()
        _anchor = State(initialValue: existing?.anchor ?? defaultAnchor)
    }

    private var canSave: Bool {
        let named = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let scheduled = !(recurrence == .custom && customMode == .weekdays && customWeekdays.isEmpty)
        return named && scheduled
    }

    private var draft: Routine {
        var r = existing ?? Routine()
        r.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        r.emoji = emoji
        r.anchor = anchor
        r.durationMin = durationMin
        r.recurrence = recurrence
        r.customMode = customMode
        r.customWeekdays = customWeekdays
        r.customDays = customDays
        r.tasks = tasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        r.notify = notify
        return r
    }

    /// Same rule as ReminderEditor: the calendar date only shows when the date
    /// itself matters to the schedule.
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
            Text(existing == nil ? "New routine" : "Edit routine")
                .font(AppFont.headline)
                .foregroundStyle(p.foreground)

            TextField("Morning routine...", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.body)

            emojiRow(p)

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
                Text("Starts")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
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

                Spacer(minLength: 12)

                Text("for \(durationMin) min")
                    .font(AppFont.callout)
                    .monospacedDigit()
                    .foregroundStyle(p.foreground)
                Stepper("", value: $durationMin, in: 5...240, step: 5)
                    .labelsHidden()
            }
            .frame(maxWidth: .infinity)

            if let note = scheduleNote {
                Text(note)
                    .font(AppFont.caption)
                    .foregroundStyle(draft.monthlyDayClamped() ? p.warn : p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            taskList(p)

            Toggle(isOn: $notify) {
                Text("Nudge me when the window opens")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(p.accent)
            .help("A gentle notification at the routine's start time. Turn it off to start by yourself.")

            HStack {
                Spacer()
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
        .frame(width: 400)
        .background(p.background)
    }

    /// A circular emoji picker button used for TASK rows: a "+" while empty, the
    /// chosen emoji once set. Tapping it opens the macOS emoji palette (see
    /// EmojiField); it never accepts typed text and shows no caret.
    private func emojiCircle(_ emoji: Binding<String>, p: Palette) -> some View {
        ZStack {
            Circle()
                .fill(p.surface)
                .overlay(Circle().stroke(p.surfaceBorder, lineWidth: 1))
            // SwiftUI draws the glyph; EmojiField is an invisible input on top.
            if emoji.wrappedValue.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.muted)
            } else {
                Text(emoji.wrappedValue)
                    .font(.system(size: 14))
            }
            EmojiField(emoji: emoji)
        }
        .frame(width: 26, height: 26)
    }

    /// The routine title's emoji row: a "+" picker that always stays a "+", then
    /// a transient circle for a freely-picked emoji (if any), then the curated
    /// quick-picks. Selecting any circle highlights it; the "+" only opens the
    /// system palette and never becomes the emoji itself.
    private func emojiRow(_ p: Palette) -> some View {
        HStack(spacing: 6) {
            titlePlusPicker(p)
                .help("Pick any emoji from the system palette.")

            if !customEmoji.isEmpty {
                selectableEmoji(customEmoji, p: p)
            }

            ForEach(Self.curatedEmoji, id: \.self) { option in
                selectableEmoji(option, p: p)
            }
        }
    }

    /// The always-"+" title picker. The hidden EmojiField captures the palette's
    /// pick into a buffer; we lift it into the transient custom circle and select
    /// it, then clear the buffer so the "+" never turns into the emoji.
    private func titlePlusPicker(_ p: Palette) -> some View {
        ZStack {
            Circle()
                .fill(p.surface)
                .overlay(Circle().stroke(p.surfaceBorder, lineWidth: 1))
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.muted)
            EmojiField(emoji: $titlePickerBuffer)
        }
        .frame(width: 26, height: 26)
        .onChange(of: titlePickerBuffer) { _, picked in
            guard !picked.isEmpty else { return }
            customEmoji = picked
            emoji = picked
            titlePickerBuffer = ""
        }
    }

    /// A selectable emoji circle (curated or the transient custom one): darker
    /// fill + accent ring when it's the chosen emoji. Tap again to clear.
    private func selectableEmoji(_ value: String, p: Palette) -> some View {
        let on = emoji == value
        return Button {
            emoji = on ? "" : value
        } label: {
            Text(value)
                .font(.system(size: 14))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(on ? p.accent.opacity(0.25) : p.surface)
                        .overlay(Circle().stroke(on ? p.accent : p.surfaceBorder, lineWidth: 1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// The repeating checklist: one editable row per task (emoji + title +
    /// remove), and an add button. Past six rows the list scrolls internally
    /// instead of growing the sheet.
    @ViewBuilder
    private func taskList(_ p: Palette) -> some View {
        let rows = VStack(alignment: .leading, spacing: 6) {
            ForEach($tasks) { $task in
                HStack(spacing: 6) {
                    emojiCircle($task.emoji, p: p)
                        .help("Tap to pick an emoji for this task. Optional.")
                    TextField("Make the bed...", text: $task.title)
                        .textFieldStyle(.roundedBorder)
                        .font(AppFont.body)
                    Button {
                        tasks.removeAll { $0.id == task.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(p.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this task")
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Checklist")
                .font(AppFont.callout)
                .foregroundStyle(p.foreground)

            if tasks.count > 6 {
                ScrollView {
                    rows
                }
                .frame(height: 6 * 30)
            } else {
                rows
            }

            Button {
                tasks.append(RoutineTask())
            } label: {
                Label("Add a task", systemImage: "plus")
                    .font(AppFont.caption)
                    .foregroundStyle(p.accent)
            }
            .buttonStyle(.plain)
        }
    }

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
