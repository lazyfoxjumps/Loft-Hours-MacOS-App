import Foundation

/// Headless verification of the log-writing path. Builds a representative
/// completed session, writes it through the real SessionStore into a temp
/// directory (same code path as the real ~/Documents/study-log writer), then
/// prints the resulting path and file contents.
enum SelfTest {
    static func run() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-selftest-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)

        let store = SessionStore(config: AppConfig(logDirectory: tmp))

        var s = Session(
            startedAt: Date(timeIntervalSince1970: 1_748_620_200), // fixed instant for stable output
            durationMin: 25,
            tasks: ["finish the intro section of the Q2 doc"],
            deliverable: "intro section drafted",
            energyStart: .medium
        )
        s.endedAt = s.startedAt.addingTimeInterval(25 * 60)
        s.delivered = "intro drafted, outlined section 2"
        s.energyEnd = .low
        s.nextStep = "write section 2 prose, ~40 min"
        s.notes = "drifted to email around minute 15"
        s.reflection = "block email harder next time"

        do {
            let url = try store.write(s)
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: tmp.path, with: "<log_dir>")
            print("SELFTEST: wrote log to \(relative)")
            print("SELFTEST: full path \(url.path)")
            print("----- file contents -----")
            print(contents)
            print("----- end contents -----")
            print("SELFTEST: OK")
        } catch {
            print("SELFTEST: FAILED \(error)")
            exit(1)
        }
    }

    /// Headless drive of the Phase 2 state machine: intake -> focus -> break ->
    /// another focus block -> wrap-up -> log, asserting transitions and that the
    /// multi-block log carries the right block count, duration, and check-in notes.
    @MainActor
    static func runControllerFlow() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-flow-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let controller = SessionController(store: SessionStore(config: AppConfig(logDirectory: tmp)))

        controller.startSession(tasks: ["multi block test", "second task"], durationMin: 25, deliverable: "draft", energy: .high)
        precondition(controller.phase == .running, "FLOW: expected running after start")
        precondition(controller.blocks == 1, "FLOW: expected block 1")

        controller.finishBlock()
        precondition(controller.phase == .breakTime, "FLOW: expected breakTime after finishBlock")

        controller.startAnotherBlock(checkIn: "block one done, going again")
        precondition(controller.phase == .running, "FLOW: expected running after another block")
        precondition(controller.blocks == 2, "FLOW: expected block 2")

        controller.finishToWrapUp(checkIn: "block two done")
        precondition(controller.phase == .wrapUp, "FLOW: expected wrapUp")

        controller.completeWrapUp(completedTasks: ["multi block test"], otherDelivered: "fixed a typo", nextStep: "block three tomorrow", energyEnd: .low, reflection: "good momentum")

        guard case let .done(path) = controller.phase, !path.hasPrefix("ERROR") else {
            print("FLOW: FAILED to write log, phase=\(controller.phase)")
            exit(1)
        }
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "<unreadable>"
        print("FLOW: multi-block log at \(path.replacingOccurrences(of: tmp.path, with: "<log_dir>"))")
        print("----- file contents -----")
        print(contents)
        print("----- end contents -----")
        precondition(contents.contains("blocks: 2"), "FLOW: expected blocks: 2")
        precondition(contents.contains("duration_min: 50"), "FLOW: expected duration_min: 50")
        precondition(contents.contains("block one done"), "FLOW: expected first check-in note")
        precondition(contents.contains("block two done"), "FLOW: expected second check-in note")
        precondition(contents.contains("- [x] multi block test"), "FLOW: expected checked task in Done section")
        precondition(contents.contains("- [ ] second task"), "FLOW: expected unchecked task in Done section")
        precondition(contents.contains("- [x] (other) fixed a typo"), "FLOW: expected Other line in Done section")
        precondition(contents.contains("delivered: multi block test; fixed a typo"), "FLOW: expected composed delivered line")
        print("FLOW: OK")
    }

    /// Headless check of the rollup math + report writer: write three sessions on
    /// consecutive days into a temp log dir, then verify counts, streak, the
    /// written report, and the < 3-sessions insufficient guard.
    static func runRollupTest() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-rollup-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let cfg = AppConfig(logDirectory: tmp)
        let store = SessionStore(config: cfg)

        // Fixed mid-month instant so the window/streak math never straddles a
        // month or week boundary on the day this runs.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd-HHmm"
        let now = fmt.date(from: "2026-06-15-1000")!
        let cal = Calendar.current

        for d in 0..<3 {
            let start = cal.date(byAdding: .day, value: -d, to: now)!
            var s = Session(startedAt: start, durationMin: 25, tasks: ["goal \(d)"], deliverable: "done look", energyStart: .medium)
            s.endedAt = start.addingTimeInterval(25 * 60)
            s.delivered = d == 2 ? "" : "shipped \(d)"   // 2 of 3 delivered
            s.energyEnd = .low
            s.nextStep = "next \(d)"
            s.reflection = "reflection \(d)"
            do { try store.write(s) } catch { print("ROLLUP: FAILED write \(error)"); exit(1) }
        }

        let svc = RollupService(reader: LogReader(config: cfg))
        let r = svc.rollup(.month, now: now, calendar: cal)
        precondition(r.sessionCount == 3, "ROLLUP: expected 3 sessions, got \(r.sessionCount)")
        precondition(r.totalFocusMinutes == 75, "ROLLUP: expected 75 min, got \(r.totalFocusMinutes)")
        precondition(!r.insufficient, "ROLLUP: 3 sessions should not be insufficient")
        precondition(r.dayStreak == 3, "ROLLUP: expected streak 3, got \(r.dayStreak)")
        precondition(r.deliveredCount == 2, "ROLLUP: expected 2 delivered, got \(r.deliveredCount)")

        let url: URL
        do { url = try svc.writeReport(r, now: now) } catch { print("ROLLUP: FAILED report \(error)"); exit(1) }
        precondition(FileManager.default.fileExists(atPath: url.path), "ROLLUP: report not written")

        // Empty window trips the insufficient guard.
        let empty = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-rollup-empty-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let r2 = RollupService(reader: LogReader(config: AppConfig(logDirectory: empty))).rollup(.week, now: now, calendar: cal)
        precondition(r2.insufficient && r2.sessionCount == 0, "ROLLUP: empty window should be insufficient")
        print("ROLLUP: OK")
    }

    /// Headless check of the crash-safe orphan sweep: drop an active-session.json
    /// in a temp log dir, sweep it, and verify it moved into abandoned/.
    static func runOrphanSweepTest() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-sweep-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let reader = LogReader(config: AppConfig(logDirectory: tmp))

        reader.writeActive(ActiveSession(
            startedAt: Date(timeIntervalSince1970: 1_748_620_200),
            goal: "crashed session", deliverable: "d", energyStart: .high,
            plannedFocusMinutes: 25, blocks: 1, checkInNotes: [], phaseRaw: "running"
        ))
        let activePath = tmp.appendingPathComponent("active-session.json").path
        precondition(FileManager.default.fileExists(atPath: activePath), "SWEEP: setup write failed")

        precondition(reader.sweepOrphan(), "SWEEP: expected an orphan to sweep")
        precondition(!FileManager.default.fileExists(atPath: activePath), "SWEEP: active file should be gone")

        let abandoned = tmp.appendingPathComponent("abandoned").path
        let files = (try? FileManager.default.contentsOfDirectory(atPath: abandoned)) ?? []
        precondition(files.count == 1, "SWEEP: expected 1 abandoned file, got \(files.count)")
        precondition(!reader.sweepOrphan(), "SWEEP: second sweep should find nothing")
        print("SWEEP: OK")
    }
}
