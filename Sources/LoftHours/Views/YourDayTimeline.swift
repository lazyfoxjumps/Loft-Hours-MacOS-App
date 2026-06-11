import SwiftUI

/// The "Your day" rail on the home screen: today's reminders in time order on
/// a vertical timeline, a NOW marker showing where in the day you are, past
/// items faded with a done tag, and a quick-add pill for new reminders.
///
/// Layout contract: every row has a FIXED height so the rail hugs its content
/// instead of soaking up the window's spare vertical space (which used to
/// shove the start button into the footer). Past `maxVisibleRows` the rail
/// scrolls internally rather than growing.
struct YourDayTimeline: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var reminderService: ReminderService

    @State private var showQuickAdd = false
    /// The rail row currently under the pointer, for the edit affordance.
    @State private var hoveredRow: UUID? = nil
    /// Ticks the view over once a minute so the NOW marker and done fades move
    /// without the user touching anything.
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let rowHeight: CGFloat = 30
    private static let markerHeight: CGFloat = 22
    private static let maxVisibleRows = 4

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
                pill("Remind me", icon: "plus", p: p) { showQuickAdd = true }
                    .help("Add a task reminder or a recurring time-to-focus nudge.")
                pill("All reminders", icon: "list.bullet", p: p) { controller.showReminders = true }
                    .help("See and edit every reminder, including ones not firing today.")
            }

            if entries.isEmpty {
                Text("Nothing on your list yet. Add a reminder to get a scheduled notification from me.")
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

    @ViewBuilder
    private func rail(_ p: Palette) -> some View {
        let past = entries.filter { $0.time < now }
        let upcoming = entries.filter { $0.time >= now }
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

    /// One reminder occurrence. The whole row is a button that jumps straight
    /// to this reminder's edit form in the All reminders sheet.
    private func row(_ entry: Entry, past: Bool, p: Palette) -> some View {
        Button {
            controller.reminderToEdit = entry.reminder
            controller.showReminders = true
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
        .help("Edit this reminder")
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
