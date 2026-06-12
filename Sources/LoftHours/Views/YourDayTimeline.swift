import SwiftUI

/// The "Your day" rail on the home screen: today's reminders and routines in
/// time order on a vertical timeline, a NOW marker showing where in the day
/// you are, past items faded with a done tag, and quick pills for adding and
/// managing both. When a routine's window is open (or about to open), a single
/// prominent start pill appears under the rail.
///
/// Layout contract: every row has a FIXED height so the rail hugs its content
/// instead of soaking up the window's spare vertical space (which used to
/// shove the start button into the footer). Past `maxVisibleRows` the rail
/// scrolls internally rather than growing.
struct YourDayTimeline: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var reminderService: ReminderService
    @EnvironmentObject private var routineService: RoutineService
    @EnvironmentObject private var routineTracker: RoutineTracker

    @State private var showQuickAdd = false
    /// The rail row currently under the pointer, for the edit affordance.
    @State private var hoveredRow: UUID? = nil
    /// Ticks the view over once a minute so the NOW marker, done fades, and the
    /// start pill move without the user touching anything.
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let rowHeight: CGFloat = 30
    private static let markerHeight: CGFloat = 22
    private static let maxVisibleRows = 4
    /// How long before its window opens a routine's start pill shows up.
    private static let startLeadMinutes = 10

    private enum Payload {
        case reminder(Reminder)
        case routine(Routine, window: ClosedRange<Date>, doneToday: Bool)
    }

    private struct Entry: Identifiable {
        let id: UUID
        let time: Date
        let payload: Payload

        /// Whether the row sits above the NOW marker: a fired reminder, a
        /// routine whose window has closed, or a routine already done today.
        func isPast(now: Date) -> Bool {
            switch payload {
            case .reminder:
                return time < now
            case .routine(_, let window, let doneToday):
                return doneToday || window.upperBound < now
            }
        }
    }

    /// Today's occurrences of the enabled reminders and routines, in time order.
    private var entries: [Entry] {
        let reminders = reminderService.reminders
            .filter(\.enabled)
            .compactMap { r in
                r.occurrenceToday(now: now).map { Entry(id: r.id, time: $0, payload: .reminder(r)) }
            }
        let routines = routineService.routines
            .filter(\.enabled)
            .compactMap { r -> Entry? in
                guard let window = r.windowToday(now: now) else { return nil }
                let done = routineTracker.entryToday(for: r.id, now: now)?.finishedAt != nil
                return Entry(id: r.id, time: window.lowerBound, payload: .routine(r, window: window, doneToday: done))
            }
        return (reminders + routines).sorted { $0.time < $1.time }
    }

    /// The one routine the start pill offers: its window is open now (or opens
    /// within the lead time), it isn't done today, and it's the nearest such
    /// routine. Only ever one pill, usually zero.
    private var startCandidate: Routine? {
        routineService.routines
            .filter(\.enabled)
            .compactMap { r -> (Routine, Date)? in
                guard let window = r.windowToday(now: now) else { return nil }
                let lead = window.lowerBound.addingTimeInterval(-TimeInterval(Self.startLeadMinutes * 60))
                guard now >= lead, now <= window.upperBound else { return nil }
                guard routineTracker.entryToday(for: r.id, now: now)?.finishedAt == nil else { return nil }
                return (r, window.lowerBound)
            }
            .min { $0.1 < $1.1 }?.0
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your day")
                    .font(AppFont.headline)
                    .foregroundStyle(p.foreground)
                Spacer()
                pill("Remind me", icon: "plus", p: p) { showQuickAdd = true }
                    .help("Add a task reminder or a recurring time-to-focus nudge.")
                pill("All reminders", icon: "list.bullet", p: p) { controller.showReminders = true }
                    .help("See and edit every reminder, including ones not firing today.")
                pill("Routines", icon: "checklist", p: p) { controller.showRoutines = true }
                    .help("Recurring time blocks with their own checklist, like a morning routine.")
            }

            if entries.isEmpty {
                Text("Nothing on your list yet. Add a reminder to get a scheduled notification from me.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            } else {
                rail(p)
            }

            if let routine = startCandidate {
                startPill(routine, p)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
        )
        .onReceive(clock) { now = $0 }
        .popover(isPresented: $showQuickAdd, arrowEdge: .bottom) {
            ReminderEditor(
                onSave: { reminder in
                    reminderService.add(reminder)
                    showQuickAdd = false
                },
                onCancel: { showQuickAdd = false }
            )
            .environmentObject(theme)
        }
    }

    @ViewBuilder
    private func rail(_ p: Palette) -> some View {
        let past = entries.filter { $0.isPast(now: now) }
        let upcoming = entries.filter { !$0.isPast(now: now) }
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(past) { row($0, past: true, p: p) }
            nowMarker(p)
            ForEach(upcoming) { row($0, past: false, p: p) }
        }

        // Cap the rail at maxVisibleRows; a long list scrolls inside instead
        // of pushing the start button down.
        if entries.count > Self.maxVisibleRows {
            ScrollView {
                rows
            }
            .frame(height: CGFloat(Self.maxVisibleRows) * Self.rowHeight + Self.markerHeight)
        } else {
            rows
        }
    }

    /// One occurrence on the rail. The whole row is a button that opens the
    /// item's editor directly in a popup, no list in between.
    private func row(_ entry: Entry, past: Bool, p: Palette) -> some View {
        Button {
            switch entry.payload {
            case .reminder(let reminder):
                controller.reminderToEdit = reminder
            case .routine(let routine, _, _):
                controller.routineToEdit = routine
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(entry.time, style: .time)
                    .font(AppFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(past ? p.muted : p.foreground)
                    .frame(width: 58, alignment: .trailing)

                ZStack {
                    Rectangle()
                        .fill(p.surfaceBorder)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                    Circle()
                        .fill(past ? p.muted : p.accent)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 12)

                switch entry.payload {
                case .reminder(let reminder):
                    Image(systemName: reminder.kind == .focusNudge ? "timer" : "bell")
                        .font(.system(size: 10))
                        .foregroundStyle(past ? p.muted : p.accent)

                    Text(reminder.displayTitle)
                        .font(AppFont.callout)
                        .foregroundStyle(p.foreground)
                        .lineLimit(1)

                case .routine(let routine, let window, _):
                    routineChip(routine, window: window, past: past, p: p)
                }

                // Reminders above the marker have fired, so they read "done".
                // A routine only earns the tag from the tracker; a window that
                // slipped by unrun just fades without a label.
                if past, showsDoneTag(entry) {
                    Text("done")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(p.surface))
                        .overlay(Capsule().stroke(p.surfaceBorder, lineWidth: 1))
                }

                Spacer(minLength: 0)

                if hoveredRow == entry.id {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(p.muted)
                        .padding(.trailing, 4)
                }
            }
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredRow == entry.id ? p.accent.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(past ? 0.5 : 1)
        .onHover { hovering in
            hoveredRow = hovering ? entry.id : (hoveredRow == entry.id ? nil : hoveredRow)
        }
        .help(helpText(for: entry))
    }

    private func showsDoneTag(_ entry: Entry) -> Bool {
        switch entry.payload {
        case .reminder: return true
        case .routine(_, _, let doneToday): return doneToday
        }
    }

    private func helpText(for entry: Entry) -> String {
        switch entry.payload {
        case .reminder: return "Edit this reminder"
        case .routine: return "Edit this routine"
        }
    }

    /// A routine's rail row content: a small rounded chip so routines read as
    /// blocks among the reminders' plain rows, with the window's time range.
    private func routineChip(_ routine: Routine, window: ClosedRange<Date>, past: Bool, p: Palette) -> some View {
        HStack(spacing: 6) {
            Text(routine.displayName)
                .font(AppFont.callout)
                .foregroundStyle(p.foreground)
                .lineLimit(1)
            Text("\(timeText(window.lowerBound)) - \(timeText(window.upperBound))")
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(p.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(p.accent.opacity(past ? 0.06 : 0.12))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.surfaceBorder, lineWidth: 1))
        )
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The one contextual start CTA: shows only while a routine's window is
    /// open (or opens in the next few minutes) and it isn't done today.
    private func startPill(_ routine: Routine, _ p: Palette) -> some View {
        Button {
            // Consumed by the routine runner in the next phase.
            controller.routineToStart = routine
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                Text("Start \(routine.displayName)")
                    .font(AppFont.nunito(13, .semibold))
            }
            .foregroundStyle(p.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule().fill(p.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("One click and the routine's countdown and checklist open.")
    }

    private func nowMarker(_ p: Palette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Now")
                .font(AppFont.caption)
                .foregroundStyle(p.accent)
                .frame(width: 58, alignment: .trailing)

            ZStack {
                Rectangle()
                    .fill(p.surfaceBorder)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(p.accent)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(p.accent.opacity(0.35), lineWidth: 3))
            }
            .frame(width: 12)

            Rectangle()
                .fill(p.accent.opacity(0.5))
                .frame(height: 1)
        }
        .frame(height: Self.markerHeight)
    }

    private func pill(_ title: String, icon: String, p: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppFont.caption)
                .foregroundStyle(p.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(p.accent.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
