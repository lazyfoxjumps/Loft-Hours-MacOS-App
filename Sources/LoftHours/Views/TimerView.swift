import SwiftUI

/// The focus block: goal pinned at top in muted small caps, a large thin
/// countdown inside a circular progress ring, and rewind / pause / skip
/// controls. In the final minute the block shifts to the warn color.
struct TimerView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    /// Time/ring/primary color: warn in the last minute, otherwise the accent.
    private func activeColor(_ p: Palette) -> Color {
        controller.isWarn ? p.warn : p.accent
    }

    var body: some View {
        let p = theme.palette
        let active = activeColor(p)

        GeometryReader { geo in
            // Ring grows with the smaller window dimension, clamped so it never
            // collapses below the minimum window or balloons past readable on a
            // 6K display. Stroke and time-font sizes follow the ring.
            let ring = min(max(min(geo.size.width, geo.size.height) * 0.55, 200), 520)
            let stroke = max(8.0, ring * 0.05)
            let timeFont = ring * 0.24
            let goalFont = max(13.0, min(ring * 0.07, 22.0))

            VStack(spacing: 30) {
                Spacer()

                Text(controller.session?.goal ?? "")
                    .font(.system(size: goalFont, weight: .medium))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)

                ZStack {
                    Circle()
                        .stroke(p.surfaceBorder, lineWidth: stroke)
                    // Stopwatch has no end to progress toward, so the ring sits
                    // full and static.
                    Circle()
                        .trim(from: 0, to: controller.isStopwatch ? 1 : controller.progress)
                        .stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: controller.progress)
                        .animation(.easeInOut(duration: 0.4), value: controller.isWarn)

                    VStack(spacing: 6) {
                        Text(controller.isStopwatch
                             ? elapsedString(controller.elapsed)
                             : timeString(controller.remaining))
                            .font(.system(size: timeFont, weight: .thin, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(active)
                            .animation(.easeInOut(duration: 0.4), value: controller.isWarn)
                        if controller.isPaused {
                            Text("Paused")
                                .font(.caption)
                                .foregroundStyle(p.muted)
                        }
                    }
                }
                .frame(width: ring, height: ring)

                controls(active: active, p: p)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(controller.isWarn ? p.warn.opacity(0.18) : Color.clear)
        }
    }

    private func controls(active: Color, p: Palette) -> some View {
        HStack(spacing: 14) {
            // No rewind on a stopwatch: there's no planned time to claw back.
            if !controller.isStopwatch {
                circleButton("backward.end.fill", primary: false, active: active, p: p) {
                    controller.rewind()
                }
            }
            circleButton(controller.isPaused ? "play.fill" : "pause.fill",
                         primary: true, active: active, p: p) {
                controller.togglePause()
            }
            circleButton(controller.isStopwatch ? "stop.fill" : "forward.end.fill",
                         primary: false, active: active, p: p) {
                controller.finishBlock()
            }
        }
    }

    private func circleButton(_ symbol: String, primary: Bool, active: Color, p: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 20 : 16, weight: .medium))
                .foregroundStyle(primary ? p.background : p.foreground)
                .frame(width: primary ? 56 : 48, height: primary ? 56 : 48)
                .background(
                    Circle()
                        .fill(primary ? active : p.surface)
                        .overlay(Circle().stroke(primary ? Color.clear : p.surfaceBorder, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Count-up display: MM:SS, growing to HH:MM:SS past an hour.
    private func elapsedString(_ t: TimeInterval) -> String {
        let total = Int(t)
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
