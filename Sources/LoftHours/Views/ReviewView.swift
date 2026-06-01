import SwiftUI
import AppKit

/// In-app weekly/monthly review, shown as a sheet over the main window. Reads
/// live from the session logs, mirrors the skill's `review week` / `review
/// month` output, and saves a markdown report alongside the logs.
struct ReviewView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    @State private var rollup: Rollup?
    @State private var reportURL: URL?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            header(p)

            ThemedSegmented(
                options: ReviewScope.allCases.map { ($0, $0.title) },
                selection: $controller.reviewScope,
                palette: p
            )

            ScrollView {
                if let r = rollup {
                    if r.insufficient {
                        insufficientCard(r, p)
                    } else {
                        stats(r, p)
                    }
                } else {
                    Text("Reading your logs...")
                        .font(AppFont.callout)
                        .foregroundStyle(p.muted)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            footer(p)
        }
        .padding(20)
        .frame(width: 420, height: 560)
        .background(p.background)
        .onAppear(perform: reload)
        .onChange(of: controller.reviewScope) { reload() }
    }

    private func reload() {
        let r = controller.rollup()
        rollup = r
        reportURL = controller.saveRollupReport(r)
    }

    // MARK: - Sections

    private func header(_ p: Palette) -> some View {
        HStack {
            Text("Review")
                .font(AppFont.heading)
                .foregroundStyle(p.foreground)
            Spacer()
            Button {
                controller.showReview = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.muted)
        }
    }

    private func stats(_ r: Rollup, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                statCard(String(format: "%.1f h", r.totalFocusHours), "focused", p)
                statCard("\(r.sessionCount)", "sessions", p)
                statCard("\(r.dayStreak)", "day streak", p)
                statCard("\(Int((r.goalDeliveredRatio * 100).rounded()))%", "goal delivered", p)
            }

            Text("Time of day: \(r.morningSessions) morning, \(r.afternoonSessions) afternoon, \(r.eveningSessions) evening")
                .font(AppFont.caption)
                .foregroundStyle(p.muted)

            if !r.suggestions.isEmpty {
                section("Suggestions", p) {
                    ForEach(r.suggestions, id: \.self) { s in
                        bullet(s, p)
                    }
                }
            }

            if !r.reflections.isEmpty {
                section("Reflections", p) {
                    ForEach(r.reflections, id: \.self) { ref in
                        bullet(ref, p)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func insufficientCard(_ r: Rollup, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(r.sessionCount == 0 ? "No sessions \(r.scope == .week ? "this week" : "this month") yet."
                                     : "Only \(r.sessionCount) session\(r.sessionCount == 1 ? "" : "s") so far.")
                .font(AppFont.title3)
                .foregroundStyle(p.foreground)
            Text("It takes at least 3 to read a pattern. Run a few more and the analytics will show up here.")
                .font(AppFont.callout)
                .foregroundStyle(p.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
        )
        .padding(.top, 8)
    }

    private func footer(_ p: Palette) -> some View {
        HStack {
            if let url = reportURL {
                Button("Reveal report in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)
                .tint(p.accent)
                .controlSize(.small)
            }
            Spacer()
            Button("Done") {
                controller.showReview = false
            }
            .buttonStyle(.borderedProminent)
            .tint(p.accent)
            .controlSize(.small)
        }
    }

    // MARK: - Bits

    private func statCard(_ value: String, _ label: String, _ p: Palette) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AppFont.title2).foregroundStyle(p.foreground)
            Text(label).font(AppFont.caption).foregroundStyle(p.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.surfaceBorder, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, _ p: Palette, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.headline).foregroundStyle(p.foreground)
            content()
        }
    }

    private func bullet(_ text: String, _ p: Palette) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(p.muted)
            Text(text).font(AppFont.callout).foregroundStyle(p.foreground)
            Spacer(minLength: 0)
        }
    }
}
