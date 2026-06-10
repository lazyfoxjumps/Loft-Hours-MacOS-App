import SwiftUI

/// The "Your day" rail on the home screen: today's reminders in time order on
/// a vertical timeline, a NOW marker showing where in the day you are, past
/// items faded with a done tag, and a quick-add pill for new reminders.
struct YourDayTimeline: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var reminderService: ReminderService

    @State private var showQuickAdd = false
    /// Ticks the view over once a minute so the NOW marker and done fades move
    /// without the user touching anything.
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct Entry: Identifiable {
        let id: UUID
        let time: Date
        let reminder: Reminder
    }

    /// Today's occurrences of the enabled reminders, in firing order.
    private var entries: [Entry] {
        reminderService.reminders
            .filter(\.enabled)
            .compactMap { r in
                r.occurrenceToday(now: now).map { Entry(id: r.id, time: $0, reminder: r) }
            }
            .sorted { $0.time < $1.time }
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your day")
                    .font(AppFont.headline)
                    .foregroundStyle(p.foreground)
                Spacer()
                quickAddPill(p)
            }

            if entries.isEmpty {
                Text("Nothing on the rail yet. Add a reminder and I'll watch the clock for you.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            } else {
                rail(p)
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

    private func rail(_ p: Palette) -> some View {
        let past = entries.filter { $0.time < now }
        let upcoming = entries.filter { $0.time >= now }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(past) { row($0, past: true, p: p) }
            nowMarker(p)
            ForEach(upcoming) { row($0, past: false, p: p) }
        }
    }

    private func row(_ entry: Entry, past: Bool, p: Palette) -> some View {
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

            Image(systemName: entry.reminder.kind == .focusNudge ? "timer" : "bell")
                .font(.system(size: 10))
                .foregroundStyle(past ? p.muted : p.accent)

            Text(entry.reminder.displayTitle)
                .font(AppFont.callout)
                .foregroundStyle(p.foreground)
                .lineLimit(1)

            if past {
                Text("done")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(p.surface))
                    .overlay(Capsule().stroke(p.surfaceBorder, lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .opacity(past ? 0.5 : 1)
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
        .frame(minHeight: 24)
    }

    private func quickAddPill(_ p: Palette) -> some View {
        Button {
            showQuickAdd = true
        } label: {
            Label("Remind me", systemImage: "plus")
                .font(AppFont.caption)
                .foregroundStyle(p.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(p.accent.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help("Add a task reminder or a recurring time-to-focus nudge.")
    }
}
