import Foundation
import SwiftUI

/// Drives a single running routine: a countdown over the routine's window and a
/// tickable checklist, nothing else. Deliberately NOT SessionController, which
/// drags markdown logs, break flow, calendar events, ActiveSession snapshots,
/// and menu-bar state along; a routine wants none of that. Completion is written
/// through RoutineTracker on every tick, so a crash mid-routine loses nothing
/// and relaunch just returns to the home screen.
@MainActor
final class RoutineRunner: ObservableObject {
    /// The routine currently running, or nil when nothing is. RootView shows the
    /// routine timer exactly when this is set.
    @Published private(set) var active: Routine?
    /// Time left on the countdown. Reaching zero soft-chimes and auto-finishes.
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isPaused: Bool = false
    /// Which tasks are ticked, mirrored from (and written through to) the
    /// tracker so a resumed run shows the earlier ticks.
    @Published private(set) var doneTaskIds: Set<UUID> = []

    private let tracker: RoutineTracker
    private let chimer = Chimer()

    /// Full length of the countdown, the denominator for the ring.
    private var total: TimeInterval = 0
    private var endDate: Date?
    private var ticker: Timer?

    init(tracker: RoutineTracker) {
        self.tracker = tracker
    }

    // MARK: - Derived

    /// Ring fill, 0...1, counting down from a full ring.
    var progress: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - remaining / total))
    }

    /// Every task ticked (and there's at least one): the finish button glows and
    /// the "finish whenever you're ready" caption appears.
    var allTasksDone: Bool {
        guard let active, !active.tasks.isEmpty else { return false }
        return active.tasks.allSatisfy { doneTaskIds.contains($0.id) }
    }

    /// "3 of 6" progress caption above the checklist.
    var progressCaption: String {
        guard let active else { return "" }
        return "\(doneTaskIds.count) of \(active.tasks.count)"
    }

    func isDone(_ taskId: UUID) -> Bool { doneTaskIds.contains(taskId) }

    // MARK: - Lifecycle

    /// Begin (or resume) a routine. Records the start in the tracker, loads any
    /// ticks already logged today, and starts the countdown. The clock runs to
    /// the window's end when started inside the window, else the full duration.
    func start(_ routine: Routine, now: Date = Date()) {
        guard active == nil else { return }
        tracker.recordStart(routine, now: now)
        active = routine
        doneTaskIds = tracker.entryToday(for: routine.id, now: now)?.doneTaskIds ?? []

        if let window = routine.windowToday(now: now), window.contains(now) {
            total = max(60, window.upperBound.timeIntervalSince(now))
        } else {
            total = TimeInterval(max(1, routine.durationMin) * 60)
        }
        remaining = total
        isPaused = false
        endDate = now.addingTimeInterval(remaining)
        startTicker()
    }

    /// Tick or untick a task. Written straight through to the tracker so a crash
    /// never loses it; ticking one on plays a soft chime.
    func toggleTask(_ taskId: UUID) {
        guard let active else { return }
        let nowDone = !doneTaskIds.contains(taskId)
        if nowDone {
            doneTaskIds.insert(taskId)
            chimer.play(.halfway)
        } else {
            doneTaskIds.remove(taskId)
        }
        tracker.setTask(taskId, done: nowDone, routineId: active.id)
    }

    func togglePause() {
        guard active != nil else { return }
        if isPaused {
            endDate = Date().addingTimeInterval(remaining)
            isPaused = false
            startTicker()
        } else {
            stopTicker()
            isPaused = true
        }
    }

    /// Finish the routine (manual stop, all-ticked, or the countdown hitting
    /// zero). Whatever is ticked stands; finishing early is normal. Records the
    /// finish, chimes, and returns to the home screen.
    func finish() {
        guard let active else { return }
        stopTicker()
        tracker.recordFinish(active.id)
        chimer.play(.complete)
        reset()
    }

    /// Leave the routine without recording a finish (the ticks already written
    /// stand). Returns to the home screen.
    func abandon() {
        stopTicker()
        reset()
    }

    private func reset() {
        active = nil
        remaining = 0
        total = 0
        isPaused = false
        doneTaskIds = []
        endDate = nil
    }

    // MARK: - Ticker

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let endDate, !isPaused else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }
}
