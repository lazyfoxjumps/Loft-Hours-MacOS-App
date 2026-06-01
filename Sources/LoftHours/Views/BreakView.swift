import SwiftUI

/// Between focus blocks: a one-line check-in, a rest countdown in the break
/// color, a rotating reminder, then the choice to run another block or wrap up.
struct BreakView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    @State private var checkIn: String = ""

    var body: some View {
        let p = theme.palette
        GeometryReader { geo in
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text("Block \(controller.blocks) done.")
                        .font(AppFont.heading)
                        .foregroundStyle(p.foreground)
                    if let goal = controller.session?.goal {
                        Text("Good job on completing: \(goal)")
                            .font(AppFont.callout)
                            .foregroundStyle(p.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 12)

                breakRing(p, viewportSize: geo.size)

                Text(controller.isBreakOver ? "Break's over, ready when you are." : controller.currentReminder)
                    .font(AppFont.callout)
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("So, how's it going so far? (optional)")
                        .font(AppFont.headline)
                        .foregroundStyle(p.foreground)
                    TextField("Log the progress, or leave it blank", text: $checkIn, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    Button {
                        controller.finishToWrapUp(checkIn: checkIn)
                    } label: {
                        Text("Finish and log").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .tint(p.accent)

                    Button {
                        controller.startAnotherBlock(checkIn: checkIn)
                        checkIn = ""
                    } label: {
                        Text("Another block").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(p.accent)
                }
                }
                .frame(maxWidth: 460)
                .padding(28)
                Spacer(minLength: 0)
            }
            .frame(minHeight: geo.size.height)
        }
        }
    }

    private func breakRing(_ p: Palette, viewportSize: CGSize) -> some View {
        // BreakView lives inside a ScrollView with other content, so we scale
        // by viewport height (rather than the larger window dimension) to stay
        // proportional. Clamped to keep the ring readable on tiny windows and
        // sensible on huge ones.
        let ring = min(max(viewportSize.height * 0.32, 150), 320)
        let stroke = max(8.0, ring * 0.06)
        let timeFont = ring * 0.235

        return ZStack {
            Circle()
                .stroke(p.surfaceBorder, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: controller.breakProgress)
                .stroke(p.breakColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: controller.breakProgress)

            VStack(spacing: 2) {
                Text(timeString(controller.breakRemaining))
                    .font(.system(size: timeFont, weight: .thin, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(controller.isBreakOver ? p.muted : p.breakColor)
                Text("break")
                    .font(AppFont.caption)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(p.muted)
            }
        }
        .frame(width: ring, height: ring)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
