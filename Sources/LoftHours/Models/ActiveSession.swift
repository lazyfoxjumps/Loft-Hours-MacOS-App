import Foundation

/// Crash-safe snapshot of a live session. Written to
/// `<log_dir>/active-session.json` on session start and each block transition,
/// and deleted on a clean wrap-up. If the app crashes mid-session, the orphan
/// left behind is swept to `<log_dir>/abandoned/` on the next launch (never
/// auto-resumed, per the skill spec).
struct ActiveSession: Codable {
    var startedAt: Date
    var goal: String
    /// Intake tasks. Optional so snapshots written before multi-task support
    /// still decode (orphan sweep must not choke on an older file).
    var tasks: [String]?
    var deliverable: String
    var energyStart: Energy
    var plannedFocusMinutes: Int
    var blocks: Int
    var checkInNotes: [String]
    /// The phase the session was in when this snapshot was written
    /// ("running", "breakTime", "wrapUp"). Informational only.
    var phaseRaw: String
}
