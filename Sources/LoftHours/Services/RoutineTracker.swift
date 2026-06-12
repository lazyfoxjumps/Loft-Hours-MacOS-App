import Foundation

/// One routine's record for one day: which tasks got ticked, when it started,
/// and when (if) it finished. Name and emoji are denormalized on purpose so
/// the history still reads right after the routine is renamed or deleted.
struct RoutineDayEntry: Codable, Equatable {
    var routineId: UUID
    var name: String
    var emoji: String
    var doneTaskIds: Set<UUID> = []
    var totalTasks: Int = 0
    var startedAt: Date
    var finishedAt: Date? = nil

    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }

    /// "5/6 tasks" for the rail tags and the Review day list.
    var progressText: String {
        "\(doneTaskIds.count)/\(totalTasks) tasks"
    }

    /// An entry counts as activity once anything actually happened: a task
    /// ticked or the routine finished. Just opening the runner doesn't count.
    var countsAsActivity: Bool {
        finishedAt != nil || !doneTaskIds.isEmpty
    }
}

/// The per-day routine tracker: one human-readable JSON file living with the
/// study logs (`<log dir>/routines/routine-tracker.json`), keyed by day
/// ("yyyy-MM-dd") with one entry per routine run that day.
///
/// Deliberately NOT per-session markdown logs, so Review > Logs stays
/// uncluttered. Crash safety comes from writing on every mutation (start,
/// each task tick, finish): a crash mid-routine loses nothing and needs no
/// orphan sweep, and re-starting the same routine the same day resumes its
/// ticks via the (day, routineId) upsert.
@MainActor
final class RoutineTracker: ObservableObject {
    @Published private(set) var days: [String: [RoutineDayEntry]]

    private let fileURL: URL
    private let calendar: Calendar

    init(config: AppConfig = .default, calendar: Calendar = .current) {
        self.fileURL = config.logDirectory
            .appendingPathComponent("routines", isDirectory: true)
            .appendingPathComponent("routine-tracker.json")
        self.calendar = calendar
        self.days = Self.decode(try? Data(contentsOf: fileURL))
    }

    // MARK: - Recording

    /// Record that a routine started (or resumed) today. Upserts on
    /// (day, routineId): a re-run keeps the earlier ticks, refreshes the
    /// denormalized name/emoji/task count, and clears finishedAt so the run
    /// reads as in-progress again.
    func recordStart(_ routine: Routine, now: Date = Date()) {
        mutate(day: now) { entries in
            if let idx = entries.firstIndex(where: { $0.routineId == routine.id }) {
                entries[idx].name = routine.name
                entries[idx].emoji = routine.emoji
                entries[idx].totalTasks = routine.tasks.count
                entries[idx].finishedAt = nil
                // Drop ticks for tasks that no longer exist on the routine.
                let valid = Set(routine.tasks.map(\.id))
                entries[idx].doneTaskIds.formIntersection(valid)
            } else {
                entries.append(RoutineDayEntry(
                    routineId: routine.id,
                    name: routine.name,
                    emoji: routine.emoji,
                    totalTasks: routine.tasks.count,
                    startedAt: now
                ))
            }
        }
    }

    /// Tick or untick one task on today's entry. Written to disk immediately,
    /// so a crash never loses a tick.
    func setTask(_ taskId: UUID, done: Bool, routineId: UUID, now: Date = Date()) {
        mutate(day: now) { entries in
            guard let idx = entries.firstIndex(where: { $0.routineId == routineId }) else { return }
            if done {
                entries[idx].doneTaskIds.insert(taskId)
            } else {
                entries[idx].doneTaskIds.remove(taskId)
            }
        }
    }

    /// Mark today's run finished (early finishes included; whatever is ticked
    /// stands).
    func recordFinish(_ routineId: UUID, now: Date = Date()) {
        mutate(day: now) { entries in
            guard let idx = entries.firstIndex(where: { $0.routineId == routineId }) else { return }
            entries[idx].finishedAt = now
        }
    }

    // MARK: - Reading

    /// All routine entries recorded on `day`, in start order.
    func entries(on day: Date) -> [RoutineDayEntry] {
        (days[Self.dayKey(day, calendar: calendar)] ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    /// Today's entry for one routine, if it ran (or is running) today.
    func entryToday(for routineId: UUID, now: Date = Date()) -> RoutineDayEntry? {
        days[Self.dayKey(now, calendar: calendar)]?.first { $0.routineId == routineId }
    }

    /// Routine activity per day (entries where something actually happened),
    /// keyed by startOfDay, for the Review calendar's intensity circles.
    func activityCounts() -> [Date: Int] {
        var out: [Date: Int] = [:]
        for (key, entries) in days {
            guard let day = Self.day(fromKey: key, calendar: calendar) else { continue }
            let active = entries.filter(\.countsAsActivity).count
            if active > 0 { out[day] = active }
        }
        return out
    }

    // MARK: - Persistence (pure helpers, covered by --selftest)

    nonisolated static func decode(_ data: Data?) -> [String: [RoutineDayEntry]] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [RoutineDayEntry]].self, from: data)) ?? [:]
    }

    nonisolated static func encode(_ days: [String: [RoutineDayEntry]]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(days)
    }

    /// "yyyy-MM-dd" in the given calendar's time zone, the tracker's day key.
    nonisolated static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func day(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return calendar.date(from: c)
    }

    private func mutate(day: Date, _ change: (inout [RoutineDayEntry]) -> Void) {
        var entries = days[Self.dayKey(day, calendar: calendar)] ?? []
        change(&entries)
        days[Self.dayKey(day, calendar: calendar)] = entries
        persist()
    }

    private func persist() {
        guard let data = Self.encode(days) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
