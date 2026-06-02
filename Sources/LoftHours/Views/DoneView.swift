import SwiftUI
import AppKit

/// Confirmation that the log was written, with a way to reveal it and start again.
struct DoneView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore
    let logPath: String

    private var isError: Bool { logPath.hasPrefix("ERROR:") }

    var body: some View {
        let p = theme.palette
        VStack(spacing: 20) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(isError ? p.warn : p.done)

            Text(isError ? "Hmm, I couldn't save that one" : "All logged. Nice work today.")
                .font(AppFont.heading)
                .foregroundStyle(p.foreground)

            Text(logPath)
                .font(isError ? AppFont.callout : AppFont.caption)
                .foregroundStyle(p.muted)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !isError {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
                }
                .buttonStyle(.bordered)
                .tint(p.accent)
            }

            Button("Go again") {
                controller.reset()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(p.accent)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
