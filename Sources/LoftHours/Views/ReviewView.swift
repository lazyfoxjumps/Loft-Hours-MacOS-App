import SwiftUI
import AppKit

/// In-app weekly/monthly review plus the session log browser, shown as a sheet
/// over the main window. Week and Month read live from the session logs and
/// mirror the skill's `review week` / `review month` output (saving a markdown
/// report alongside the logs). Logs lists every session in readable form so
/// nobody needs to know what a .md file is.
struct ReviewView: View {
    @EnvironmentObject private var controller: SessionController
    @EnvironmentObject private var theme: ThemeStore

    /// Which pane the sheet shows. Week/Month map onto the controller's
    /// `reviewScope` (which the menu bar also sets); Logs is sheet-local.
    enum Pane: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case logs = "Logs"
    }

    @State private var pane: Pane = .week
    @State private var rollup: Rollup?
    @State private var reportURL: URL?
    @State private var logs: [ParsedLog] = []
    /// The log open in the detail card; nil shows the list.
    @State private var selectedLog: ParsedLog?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            header(p)

            ThemedSegmented(
                options: Pane.allCases.map { ($0, $0.rawValue) },
                selection: $pane,
                palette: p
            )

            ScrollView {
                switch pane {
                case .week, .month:
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
                case .logs:
                    if let log = selectedLog {
                        logDetail(log, p)
                    } else {
                        logList(p)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            footer(p)
        }
        .padding(20)
        .frame(width: 420, height: 560)
        .background(p.background)
        .onAppear {
            pane = controller.reviewScope == .month ? .month : .week
            reload()
        }
        .onChange(of: pane) {
            switch pane {
            case .week: controller.reviewScope = .week
            case .month: controller.reviewScope = .month
            case .logs: selectedLog = nil
            }
            reload()
        }
    }

    private func reload() {
        switch pane {
        case .week, .month:
            let r = controller.rollup()
            rollup = r
            reportURL = controller.saveRollupReport(r)
        case .logs:
            logs = controller.allLogs()
        }
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

    // MARK: - Logs pane

    /// Logs grouped by calendar month, newest group (and newest log) first.
    private var groupedLogs: [(title: String, logs: [ParsedLog])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var groups: [String: [ParsedLog]] = [:]
        for log in logs {
            let key = fmt.string(from: log.startedAt)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(log)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private func logList(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if logs.isEmpty {
                Text("No sessions logged yet. Finish a focus session and it'll show up here.")
                    .font(AppFont.callout)
                    .foregroundStyle(p.muted)
                    .padding(.top, 12)
            } else {
                ForEach(groupedLogs, id: \.title) { group in
                    Text(group.title)
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .padding(.top, 8)
                    ForEach(group.logs, id: \.url) { log in
                        logRow(log, p)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func logRow(_ log: ParsedLog, _ p: Palette) -> some View {
        Button {
            selectedLog = log
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(log))
                        .font(AppFont.callout)
                        .foregroundStyle(p.foreground)
                    Text(log.goal.isEmpty ? "(no goal noted)" : log.goal)
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(p.muted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(p.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.surfaceBorder, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowTitle(_ log: ParsedLog) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM"
        var title = "\(fmt.string(from: log.startedAt)) · \(hoursMinutes(log.durationMin)) focused"
        if log.blocks > 1 { title += " · \(log.blocks) blocks" }
        return title
    }

    private func logDetail(_ log: ParsedLog, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedLog = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12))
                        .foregroundStyle(p.accent)
                    Text(detailTitle(log))
                        .font(AppFont.callout)
                        .foregroundStyle(p.foreground)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the list")

            HStack(spacing: 8) {
                statCard(hoursMinutes(log.durationMin), "focused", p)
                statCard("\(log.blocks)", log.blocks == 1 ? "block" : "blocks", p)
                statCard(energyArc(log), "energy", p)
            }

            detailField("Goal", log.goal, p)

            if !log.doneItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Done")
                        .font(AppFont.caption)
                        .foregroundStyle(p.muted)
                    ForEach(Array(log.doneItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: item.checked ? "checkmark.square" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(item.checked ? p.accent : p.muted)
                                .padding(.top, 2)
                            Text(item.text)
                                .font(AppFont.callout)
                                .foregroundStyle(p.foreground)
                        }
                    }
                }
            }

            detailField("Notes", log.notes, p)
            detailField("Reflection", log.reflection, p, italic: true)
            detailField("Next step", log.nextStep, p)

            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([log.url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(AppFont.caption)
                        .foregroundStyle(p.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(p.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(log.url.lastPathComponent)
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            }
            .padding(.top, 4)
        }
        .padding(.top, 2)
    }

    /// A labeled text block in the detail card; hidden when the log left it blank.
    @ViewBuilder
    private func detailField(_ title: String, _ value: String, _ p: Palette, italic: Bool = false) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
                Text(value)
                    .font(AppFont.callout)
                    .italic(italic)
                    .foregroundStyle(p.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailTitle(_ log: ParsedLog) -> String {
        let day = DateFormatter()
        day.dateFormat = "EEE d MMM yyyy"
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        var title = "\(day.string(from: log.startedAt)) · \(time.string(from: log.startedAt))"
        if let end = log.endedAt {
            title += "–\(time.string(from: end))"
        }
        return title
    }

    private func hoursMinutes(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Compact "med → low" style energy arc for the stat chip.
    private func energyArc(_ log: ParsedLog) -> String {
        func short(_ e: Energy) -> String { e == .medium ? "med" : e.rawValue }
        if log.energyStart == log.energyEnd { return short(log.energyStart) }
        return "\(short(log.energyStart))→\(short(log.energyEnd))"
    }

    private func footer(_ p: Palette) -> some View {
        HStack {
            if pane != .logs, let url = reportURL {
                Button("Reveal report in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)
                .tint(p.accent)
                .controlSize(.small)
                .font(AppFont.callout)
            }
            Spacer()
            Button("Done") {
                controller.showReview = false
            }
            .buttonStyle(.borderedProminent)
            .tint(p.accent)
            .controlSize(.small)
            .font(AppFont.callout)
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
