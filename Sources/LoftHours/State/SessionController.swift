import Foundation
import SwiftUI

/// The phases of the app's loop. A session is one or more focus blocks, each
/// followed by a break, ending in wrap-up and a log.
enum AppPhase: Equatable {
    case intake
    case running     // focus block
    case breakTime   // check-in + rest between blocks
    case wrapUp
    case done(logPath: String)
}

/// Drives the full loop: intake -> focus -> break -> (focus -> break)* -> wrap-up -> log.
/// Owns the live session, the countdown clocks, and the synced audio/notification cues.
@MainActor
final class SessionController: ObservableObject {
    @Published var phase: AppPhase = .intake
    @Published private(set) var session: Session?

    // Focus clock
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isPaused: Bool = false

    // Break clock
    @Published private(set) var breakRemaining: TimeInterval = 0
    @Published private(set) var isBreakOver: Bool = false

    /// Blocks started so far this session.
    @Published private(set) var blocks: Int = 0

    let rewindSeconds: TimeInterval = 60

    private let store: SessionStore
    private let reader: LogReader
    private let chimer = Chimer()
    private let notifier: Notifier
    private let config: ConfigStore?
    private let appManager = AppManager()

    // MARK: - Review (analytics) UI state
    /// Whether the in-app Review sheet is shown (over the main window).
    @Published var showReview: Bool = false
    /// Which window the Review sheet is currently showing.
    @Published var reviewScope: ReviewScope = .week

    /// Apps closed during setup so the wrap-up can offer to reopen them.
    @Published private(set) var closedApps: [String] = []
    @Published var restoreClosedApps: Bool = true

    /// Manual Do Not Disturb state, toggled from the home screen independently
    /// of a running session. macOS gives us no way to read the real Focus
    /// state, so this is our best-effort mirror of what we last asked for.
    @Published private(set) var manualDNDOn: Bool = false

    // Focus block bookkeeping
    private var endDate: Date?
    private var ticker: Timer?
    private var effectiveTotal: TimeInterval = 0   // denominator for the ring (grows on rewind)
    private var blockTotal: TimeInterval = 0       // planned length of the current block (cue thresholds)
    private var lastBlockMinutes: Int = 25
    private var plannedFocusMinutes: Int = 0

    // Break bookkeeping
    private var breakEndDate: Date?
    private var breakTicker: Timer?
    private var breakTotal: TimeInterval = 0

    // Per-block cue flags
    private var halfwayFired = false
    private var lastMinuteFired = false

    // Accumulated check-in notes across blocks
    private var checkInNotes: [String] = []

    init(notifier: Notifier = Notifier(), store: SessionStore = SessionStore(), config: ConfigStore? = nil) {
        self.notifier = notifier
        self.store = store
        self.config = config
        self.reader = LogReader(config: store.config)
        // Crash safety: archive any session left behind by a crash, then start
        // fresh. Never auto-resume (skill spec §16).
        reader.sweepOrphan()
    }

    // MARK: - Resume

    /// The previous session's `next_step`, surfaced as the intake goal default.
    /// Nil when there's no prior log or its next step was blank.
    var resumeSuggestion: String? {
        let step = reader.latest()?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        return (step?.isEmpty == false) ? step : nil
    }

    // MARK: - Review

    func openReview(_ scope: ReviewScope) {
        reviewScope = scope
        showReview = true
    }

    /// Compute the rollup for the currently selected scope, live from the logs.
    func rollup() -> Rollup {
        RollupService(reader: reader).rollup(reviewScope, now: Date())
    }

    /// Persist the rollup's markdown report; returns the file URL (or nil on
    /// failure). Best-effort so the Review sheet still renders if the write fails.
    @discardableResult
    func saveRollupReport(_ rollup: Rollup) -> URL? {
        try? RollupService(reader: reader).writeReport(rollup, now: Date())
    }

    func requestNotificationAuthorization() {
        notifier.requestAuthorization()
    }

    // MARK: - Derived

    var progress: Double {
        guard effectiveTotal > 0 else { return 0 }
        return max(0, min(1, 1 - remaining / effectiveTotal))
    }

    var breakProgress: Double {
        guard breakTotal > 0 else { return 0 }
        return max(0, min(1, 1 - breakRemaining / breakTotal))
    }

    var isWarn: Bool {
        phase == .running && remaining > 0 && remaining <= 60
    }

    /// A rotating between-breaks reminder (water / stand / eyes).
    var currentReminder: String {
        let reminders = [
            "Drink some water.",
            "Stand up, give the legs a stretch.",
            "Look 20 feet away for 20 seconds, the eyes will thank you.",
        ]
        let idx = max(0, blocks - 1) % reminders.count
        return reminders[idx]
    }

    // MARK: - Intake -> focus

    func startSession(tasks: [String], durationMin: Int, deliverable: String, energy: Energy) {
        var s = Session(startedAt: Date(), durationMin: durationMin, tasks: tasks, deliverable: deliverable, energyStart: energy)
        s.blocks = 0
        session = s
        blocks = 0
        plannedFocusMinutes = 0
        checkInNotes = []
        setupEnvironment()
        startFocusBlock(minutes: durationMin)
        // No re-activation needed: focus apps launch with `open -g` and the DND
        // Shortcut runs non-activating, so nothing steals foreground and the
        // timer window stays put.
    }

    /// Toggle Do Not Disturb on demand from the home screen. Uses the same
    /// configured Shortcuts as the automatic session ritual. Falls back to the
    /// default shortcut names if no config is wired (e.g. previews).
    func setManualDND(_ on: Bool) {
        let focus: FocusService
        if let config {
            focus = FocusService(shortcutOn: config.focusShortcutOn, shortcutOff: config.focusShortcutOff)
        } else {
            focus = FocusService(shortcutOn: "Turn On Do Not Disturb", shortcutOff: "Turn Off Do Not Disturb")
        }
        on ? focus.enable() : focus.disable()
        manualDNDOn = on
    }

    /// Abandon the current session without writing a log and return to intake.
    /// Used by "Start another session" for people who don't want to log.
    /// The environment is left as-is so the next session continues seamlessly.
    func discardAndRestart() {
        reader.clearActive()
        stopTicker()
        stopBreakTicker()
        session = nil
        remaining = 0
        breakRemaining = 0
        effectiveTotal = 0
        blockTotal = 0
        blocks = 0
        plannedFocusMinutes = 0
        checkInNotes = []
        isPaused = false
        isBreakOver = false
        endDate = nil
        breakEndDate = nil
        phase = .intake
    }

    // MARK: - Environment setup / teardown

    private func setupEnvironment() {
        guard let config else { return }
        restoreClosedApps = config.restoreAppsAfter
        if config.focusModeEnabled {
            FocusService(shortcutOn: config.focusShortcutOn, shortcutOff: config.focusShortcutOff).enable()
            manualDNDOn = true
        }
        if config.appManagementEnabled {
            closedApps = appManager.close(config.alwaysClose)
            appManager.open(config.openForFocus)
        } else {
            closedApps = []
        }
    }

    private func teardownEnvironment() {
        guard let config else { return }
        if config.focusModeEnabled {
            FocusService(shortcutOn: config.focusShortcutOn, shortcutOff: config.focusShortcutOff).disable()
            manualDNDOn = false
        }
        if config.appManagementEnabled, restoreClosedApps, !closedApps.isEmpty {
            appManager.open(closedApps)
        }
        closedApps = []
    }

    private func startFocusBlock(minutes: Int) {
        lastBlockMinutes = minutes
        blocks += 1
        plannedFocusMinutes += minutes
        session?.blocks = blocks
        session?.durationMin = plannedFocusMinutes

        blockTotal = TimeInterval(minutes * 60)
        remaining = blockTotal
        effectiveTotal = blockTotal
        halfwayFired = false
        lastMinuteFired = false
        isPaused = false
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
        persistActive()
    }

    /// Write the crash-safe snapshot of the live session. Best-effort.
    private func persistActive() {
        guard let s = session else { return }
        let phaseRaw: String
        switch phase {
        case .running: phaseRaw = "running"
        case .breakTime: phaseRaw = "breakTime"
        case .wrapUp: phaseRaw = "wrapUp"
        default: phaseRaw = "intake"
        }
        reader.writeActive(ActiveSession(
            startedAt: s.startedAt,
            goal: s.goal,
            tasks: s.tasks,
            deliverable: s.deliverable,
            energyStart: s.energyStart,
            plannedFocusMinutes: plannedFocusMinutes,
            blocks: blocks,
            checkInNotes: checkInNotes,
            phaseRaw: phaseRaw
        ))
    }

    // MARK: - Focus controls

    func togglePause() {
        guard phase == .running else { return }
        if isPaused {
            endDate = Date().addingTimeInterval(remaining)
            isPaused = false
            startTicker()
        } else {
            stopTicker()
            isPaused = true
        }
    }

    func rewind() {
        guard phase == .running else { return }
        remaining += rewindSeconds
        if remaining > effectiveTotal { effectiveTotal = remaining }
        if !isPaused { endDate = Date().addingTimeInterval(remaining) }
    }

    /// End the focus block (natural completion or Skip) and start the break.
    func finishBlock() {
        guard phase == .running else { return }
        stopTicker()
        remaining = 0
        chimer.play(.complete)
        notifier.notify(title: "Loft Hours", body: "Block complete. Take a breath.")
        startBreak()
    }

    // MARK: - Break

    private func startBreak() {
        breakTotal = lastBlockMinutes <= 25 ? 5 * 60 : 10 * 60
        breakRemaining = breakTotal
        isBreakOver = false
        breakEndDate = Date().addingTimeInterval(breakRemaining)
        phase = .breakTime
        startBreakTicker()
    }

    /// Record an optional check-in note for the block just finished.
    func recordCheckIn(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checkInNotes.append(trimmed)
    }

    func startAnotherBlock(checkIn note: String) {
        recordCheckIn(note)
        stopBreakTicker()
        startFocusBlock(minutes: lastBlockMinutes)
    }

    func finishToWrapUp(checkIn note: String) {
        recordCheckIn(note)
        stopBreakTicker()
        session?.endedAt = Date()
        phase = .wrapUp
        persistActive()
    }

    // MARK: - Wrap-up -> log

    func completeWrapUp(completedTasks: [String], otherDelivered: String, nextStep: String, energyEnd: Energy, reflection: String) {
        guard var s = session else { return }
        s.completedTasks = completedTasks
        s.otherDelivered = otherDelivered
        let parts = completedTasks + (otherDelivered.isEmpty ? [] : [otherDelivered])
        s.delivered = parts.joined(separator: "; ")
        s.nextStep = nextStep
        s.energyEnd = energyEnd
        s.reflection = reflection
        s.notes = checkInNotes.joined(separator: "\n")
        if s.endedAt == nil { s.endedAt = Date() }
        session = s

        do {
            let url = try store.write(s)
            phase = .done(logPath: url.path)
        } catch {
            phase = .done(logPath: "ERROR: \(error.localizedDescription)")
        }
        reader.clearActive()
        teardownEnvironment()
    }

    func reset() {
        reader.clearActive()
        teardownEnvironment()
        stopTicker()
        stopBreakTicker()
        session = nil
        remaining = 0
        breakRemaining = 0
        effectiveTotal = 0
        blockTotal = 0
        blocks = 0
        plannedFocusMinutes = 0
        checkInNotes = []
        isPaused = false
        isBreakOver = false
        endDate = nil
        breakEndDate = nil
        phase = .intake
    }

    // MARK: - Focus ticker

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

        if !halfwayFired, blockTotal > 0, remaining > 0, remaining <= blockTotal / 2 {
            halfwayFired = true
            chimer.play(.halfway)
            notifier.notify(title: "Loft Hours", body: "Halfway there.")
        }
        if !lastMinuteFired, remaining > 0, remaining <= 60 {
            lastMinuteFired = true
            chimer.play(.lastMinute)
            notifier.notify(title: "Loft Hours", body: "One minute left, wrap up the thought.")
        }
        if remaining <= 0 {
            finishBlock()
        }
    }

    // MARK: - Break ticker

    private func startBreakTicker() {
        stopBreakTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.breakTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        breakTicker = timer
    }

    private func stopBreakTicker() {
        breakTicker?.invalidate()
        breakTicker = nil
    }

    private func breakTick() {
        guard let breakEndDate else { return }
        breakRemaining = max(0, breakEndDate.timeIntervalSinceNow)
        if breakRemaining <= 0 && !isBreakOver {
            isBreakOver = true
            stopBreakTicker()
            chimer.play(.halfway)
            notifier.notify(title: "Loft Hours", body: "Break's over, ready when you are.")
        }
    }
}
