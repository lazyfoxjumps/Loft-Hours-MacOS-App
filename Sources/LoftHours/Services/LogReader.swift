import Foundation

/// One parsed session log, read back from the markdown `SessionStore` writes.
struct ParsedLog {
    var url: URL
    var startedAt: Date
    var endedAt: Date?
    var durationMin: Int
    var blocks: Int
    var goal: String
    var delivered: String
    var energyStart: Energy
    var energyEnd: Energy
    var nextStep: String
    var reflection: String
}

/// Reads and parses the session logs written by `SessionStore`, and manages the
/// crash-safe `active-session.json`. Shares `AppConfig.logDirectory` with the
/// writer so reads and writes always point at the same folder.
struct LogReader {
    let config: AppConfig

    init(config: AppConfig = .default) {
        self.config = config
    }

    var logDirectory: URL { config.logDirectory }
    private var activeURL: URL { logDirectory.appendingPathComponent("active-session.json") }
    private var abandonedDir: URL { logDirectory.appendingPathComponent("abandoned", isDirectory: true) }

    // MARK: - Reading logs

    /// Every `.md` session log under `<log_dir>/YYYY/MM/`, excluding the
    /// `reviews/` and `abandoned/` subtrees.
    func allLogFiles() -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: logDirectory, includingPropertiesForKeys: nil) else { return [] }
        var result: [URL] = []
        for case let url as URL in en {
            guard url.pathExtension == "md" else { continue }
            let parts = url.pathComponents
            if parts.contains("reviews") || parts.contains("abandoned") { continue }
            result.append(url)
        }
        return result
    }

    /// Parse one log file's frontmatter (and `## Reflection` body) into a
    /// `ParsedLog`. Mirrors the exact keys `SessionStore.write` emits.
    func parse(_ url: URL) -> ParsedLog? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")

        var fm: [String: String] = [:]
        var inFront = false
        var frontDone = false
        var inReflection = false
        var reflectionLines: [String] = []

        for line in lines {
            if line == "---" {
                if !inFront && !frontDone { inFront = true }
                else if inFront { inFront = false; frontDone = true }
                continue
            }
            if inFront {
                if let c = line.firstIndex(of: ":") {
                    let key = String(line[..<c]).trimmingCharacters(in: .whitespaces)
                    let val = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
                    fm[key] = val
                }
                continue
            }
            if frontDone {
                if line.hasPrefix("## Reflection") { inReflection = true; continue }
                if line.hasPrefix("## ") { inReflection = false; continue }
                if inReflection { reflectionLines.append(line) }
            }
        }

        guard let dateStr = fm["date"] else { return nil }
        let dayFmt = Self.formatter("yyyy-MM-dd")
        let dtFmt = Self.formatter("yyyy-MM-dd HH:mm")
        let started = dtFmt.date(from: "\(dateStr) \(fm["start"] ?? "00:00")")
            ?? dayFmt.date(from: dateStr)
            ?? Date(timeIntervalSince1970: 0)
        let ended = fm["end"].flatMap { dtFmt.date(from: "\(dateStr) \($0)") }

        return ParsedLog(
            url: url,
            startedAt: started,
            endedAt: ended,
            durationMin: Int(fm["duration_min"] ?? "") ?? 0,
            blocks: Int(fm["blocks"] ?? "") ?? 1,
            goal: fm["goal"] ?? "",
            delivered: fm["delivered"] ?? "",
            energyStart: Energy(rawValue: fm["energy_start"] ?? "") ?? .medium,
            energyEnd: Energy(rawValue: fm["energy_end"] ?? "") ?? .medium,
            nextStep: fm["next_step"] ?? "",
            reflection: reflectionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The most recent session log by start time, or nil if none exist.
    func latest() -> ParsedLog? {
        allLogFiles().compactMap(parse).max(by: { $0.startedAt < $1.startedAt })
    }

    /// All logs whose start falls inside `interval`, oldest first.
    func logs(in interval: DateInterval) -> [ParsedLog] {
        allLogFiles()
            .compactMap(parse)
            .filter { interval.contains($0.startedAt) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - Active session (crash safety)

    /// Write/refresh the live-session snapshot. Best-effort: a failure here must
    /// never break a running session.
    func writeActive(_ active: ActiveSession) {
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(active)
            try data.write(to: activeURL, options: .atomic)
        } catch {
            // swallow: snapshotting is opportunistic
        }
    }

    /// Remove the snapshot after a clean wrap-up / reset.
    func clearActive() {
        try? FileManager.default.removeItem(at: activeURL)
    }

    /// If an orphaned `active-session.json` exists (left by a crash), move it to
    /// `abandoned/active-session-<timestamp>.json`. Returns true if one was
    /// swept. Never resumes it: the skill spec says always archive and start
    /// fresh, without prompting.
    @discardableResult
    func sweepOrphan() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: activeURL.path) else { return false }
        do {
            try fm.createDirectory(at: abandonedDir, withIntermediateDirectories: true)
            let stamp = Self.formatter("yyyy-MM-dd-HHmmss").string(from: Date())
            let dest = abandonedDir.appendingPathComponent("active-session-\(stamp).json")
            try fm.moveItem(at: activeURL, to: dest)
            return true
        } catch {
            // If the move fails for any reason, drop the orphan so it doesn't
            // resurface on every launch.
            try? fm.removeItem(at: activeURL)
            return false
        }
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
