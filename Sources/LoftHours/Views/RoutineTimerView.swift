import SwiftUI

/// The routine runner screen: the same visual language as TimerView (a large
/// thin countdown inside a circular ring, the routine's name where the focus
/// goal sits) with a tickable checklist below. No wrap-up, no break flow, no
/// energy or reflection prompts: finishing returns straight to the home screen.
struct RoutineTimerView: View {
    @EnvironmentObject private var runner: RoutineRunner
    @EnvironmentObject private var theme: ThemeStore

    /// Past ~6 rows the checklist scrolls internally instead of pushing the
    /// controls off the bottom, the same cap the "Your day" rail uses.
    private static let maxVisibleTasks = 6
    private static let taskRowHeight: CGFloat = 36

    var body: some View {
        let p = theme.palette
        let routine = runner.active

        GeometryReader { geo in
            // The ring no longer shares vertical space with the checklist (the
            // card sits beside it now), so it can sit a touch larger; still
            // clamped against tiny and huge windows.
            let ring = min(max(min(geo.size.width, geo.size.height) * 0.44, 170), 360)
            let stroke = max(7.0, ring * 0.05)
            let timeFont = ring * 0.24
            let nameFont = max(12.0, min(ring * 0.07, 20))
            let hasTasks = !(routine?.tasks.isEmpty ?? true)

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                // The title sits well above the timer row so it reads as a
                // prominent header rather than a label stuck to the ring.
                Text(routine?.displayName ?? "")
                    .font(AppFont.nunito(nameFont, .semibold))
                    .foregroundStyle(p.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                // Ring + its controls on the left, the framed To-Do card on the
                // right. Top-aligned so the card's top lines up with the ring's
                // top and grows downward as tasks are added. When a routine has
                // no tasks the ring column simply centers on its own.
                HStack(alignment: .top, spacing: 56) {
                    VStack(spacing: 22) {
                        ringView(p, ring: ring, stroke: stroke, timeFont: timeFont)
                        controls(p)
                    }
                    if hasTasks {
                        todoCard(routine, p: p)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ringView(_ p: Palette, ring: CGFloat, stroke: CGFloat, timeFont: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(p.surfaceBorder, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: runner.progress)
                .stroke(p.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: runner.progress)

            VStack(spacing: 6) {
                Text(timeString(runner.remaining))
                    .font(AppFont.nunito(timeFont, .thin))
                    .monospacedDigit()
                    .foregroundStyle(p.accent)
                if runner.isPaused {
                    Text("Paused")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                }
            }
        }
        .frame(width: ring, height: ring)
    }

    // MARK: - To-Do card

    @ViewBuilder
    private func todoCard(_ routine: Routine?, p: Palette) -> some View {
        if let routine, !routine.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("To-Do")
                        .font(AppFont.gaegu(24))
                        .foregroundStyle(p.foreground)
                    Spacer(minLength: 12)
                    Text(runner.progressCaption)
                        .font(AppFont.caption)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(p.muted)
                }

                let rows = VStack(spacing: 0) {
                    ForEach(routine.tasks) { task in
                        taskRow(task, p: p)
                    }
                }

                if routine.tasks.count > Self.maxVisibleTasks {
                    ScrollView {
                        rows
                    }
                    .frame(height: CGFloat(Self.maxVisibleTasks) * Self.taskRowHeight)
                } else {
                    rows
                }
            }
            .padding(16)
            .frame(minWidth: 240, maxWidth: 300, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(p.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.surfaceBorder, lineWidth: 1))
            )
        }
    }

    private func taskRow(_ task: RoutineTask, p: Palette) -> some View {
        let done = runner.isDone(task.id)
        return Button {
            runner.toggleTask(task.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(done ? p.done : p.muted)

                Text(task.displayTitle)
                    .font(AppFont.nunito(15))
                    .foregroundStyle(done ? p.muted : p.foreground)
                    .strikethrough(done, color: p.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(height: Self.taskRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    private func controls(_ p: Palette) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                circleButton(runner.isPaused ? "play.fill" : "pause.fill",
                             primary: false, glow: false, p: p) {
                    runner.togglePause()
                }
                // Stop = finish, like the stopwatch. Gains a gentle accent glow
                // once every task is ticked.
                circleButton("stop.fill", primary: true, glow: runner.allTasksDone, p: p) {
                    runner.finish()
                }
            }

            if runner.allTasksDone {
                Text(Messages.routineAllDone)
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func circleButton(_ symbol: String, primary: Bool, glow: Bool, p: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 20 : 16, weight: .medium))
                .foregroundStyle(primary ? p.background : p.foreground)
                .frame(width: primary ? 56 : 48, height: primary ? 56 : 48)
                .background(
                    Circle()
                        .fill(primary ? p.accent : p.surface)
                        .overlay(Circle().stroke(primary ? Color.clear : p.surfaceBorder, lineWidth: 1))
                        .shadow(color: glow ? p.accent.opacity(0.6) : .clear, radius: glow ? 12 : 0)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: glow)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
