import Foundation

/// Energy level, matching the skill's low/medium/high scale.
enum Energy: String, CaseIterable, Identifiable, Codable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// One focus session. Phase 1 is a single-block session; `blocks` stays at 1
/// for now and grows when the break flow lands in Phase 2.
///
/// The field names mirror the markdown frontmatter the skill writes, so logs
/// from the app and the skill stay interchangeable in `~/Documents/study-log`.
struct Session {
    var startedAt: Date
    var endedAt: Date?
    var durationMin: Int
    var blocks: Int = 1
    /// Stopwatch mode: no planned length, the clock counts up and `durationMin`
    /// is filled with the actual elapsed time as each block finishes.
    var isStopwatch: Bool = false

    /// The intake plan as a single line (tasks joined with "; "). Kept for log
    /// frontmatter parity with the skill's `goal:` field.
    var goal: String
    /// The intake plan as discrete tasks. Wrap-up turns these into the
    /// done-checklist; `goal` is their joined form.
    var tasks: [String] = []
    /// "What does done look like" from intake. Recorded for parity; the log's
    /// `delivered` is filled at wrap-up.
    var deliverable: String
    /// Wrap-up summary line (checked tasks + any "Other"), joined with "; ".
    var delivered: String = ""
    /// Which intake tasks the user checked off at wrap-up.
    var completedTasks: [String] = []
    /// Free-text "Other" things done, entered at wrap-up.
    var otherDelivered: String = ""

    var energyStart: Energy
    var energyEnd: Energy?

    var nextStep: String = ""
    var notes: String = ""
    var reflection: String = ""

    init(startedAt: Date, durationMin: Int, tasks: [String], deliverable: String, energyStart: Energy, isStopwatch: Bool = false) {
        self.startedAt = startedAt
        self.durationMin = durationMin
        self.tasks = tasks
        self.goal = tasks.joined(separator: "; ")
        self.deliverable = deliverable
        self.energyStart = energyStart
        self.isStopwatch = isStopwatch
    }
}
