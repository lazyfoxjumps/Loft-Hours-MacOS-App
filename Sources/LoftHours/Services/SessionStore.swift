import Foundation

/// Writes a finished session to a markdown file under the log directory,
/// matching the schema the skill produces:
///
///     <log_dir>/YYYY/MM/YYYY-MM-DD-HHMM.md
///
/// In Phase 4 this gains a SwiftData source-of-truth; for Phase 1 the markdown
/// file IS the record.
struct SessionStore {
    let config: AppConfig

    init(config: AppConfig = .default) {
        self.config = config
    }

    /// Write the session log. Returns the file URL on success.
    @discardableResult
    func write(_ session: Session) throws -> URL {
        let end = session.endedAt ?? Date()

        let yearFmt = Self.formatter("yyyy")
        let monthFmt = Self.formatter("MM")
        let dayFmt = Self.formatter("yyyy-MM-dd")
        let timeFmt = Self.formatter("HH:mm")
        let stampFmt = Self.formatter("yyyy-MM-dd-HHmm")

        let dir = config.logDirectory
            .appendingPathComponent(yearFmt.string(from: session.startedAt), isDirectory: true)
            .appendingPathComponent(monthFmt.string(from: session.startedAt), isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("\(stampFmt.string(from: session.startedAt)).md")

        var lines: [String] = []
        lines.append("---")
        lines.append("date: \(dayFmt.string(from: session.startedAt))")
        lines.append("start: \(timeFmt.string(from: session.startedAt))")
        lines.append("end: \(timeFmt.string(from: end))")
        lines.append("duration_min: \(session.durationMin)")
        lines.append("blocks: \(session.blocks)")
        lines.append("goal: \(session.goal)")
        lines.append("delivered: \(session.delivered)")
        lines.append("energy_start: \(session.energyStart.rawValue)")
        lines.append("energy_end: \(session.energyEnd?.rawValue ?? session.energyStart.rawValue)")
        lines.append("next_step: \(session.nextStep)")
        lines.append("---")

        // The intake plan as a done-checklist: [x] for tasks the user checked at
        // wrap-up, [ ] for the rest, plus any free-text "Other" things done.
        if !session.tasks.isEmpty || !session.otherDelivered.isEmpty {
            lines.append("")
            lines.append("## Done")
            for task in session.tasks {
                let mark = session.completedTasks.contains(task) ? "x" : " "
                lines.append("- [\(mark)] \(task)")
            }
            let other = session.otherDelivered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !other.isEmpty {
                lines.append("- [x] (other) \(other)")
            }
        }

        lines.append("")
        lines.append("## Notes")
        lines.append(session.notes.isEmpty ? "" : session.notes)

        let reflection = session.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reflection.isEmpty {
            lines.append("")
            lines.append("## Reflection")
            lines.append(reflection)
        }
        lines.append("")

        let contents = lines.joined(separator: "\n")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
