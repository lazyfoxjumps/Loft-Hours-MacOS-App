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

    /// Headless drive of a stopwatch session: count-up block with no end date,
    /// rewind a no-op, pause/resume works, Stop books the real elapsed time
    /// (sub-minute rounds up to 1) and the break defaults to 5 minutes.
    @MainActor
    static func runStopwatchTest() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-stopwatch-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let controller = SessionController(store: SessionStore(config: AppConfig(logDirectory: tmp)))

        controller.startSession(tasks: ["stopwatch test"], durationMin: 0, deliverable: "d", energy: .medium, isStopwatch: true)
        precondition(controller.phase == .running, "STOPWATCH: expected running after start")
        precondition(controller.isStopwatch, "STOPWATCH: controller should report stopwatch mode")
        precondition(controller.blocks == 1, "STOPWATCH: expected block 1")
        precondition(controller.remaining == 0, "STOPWATCH: no countdown should be armed")
        precondition(controller.session?.durationMin == 0, "STOPWATCH: duration should start at 0")

        controller.togglePause()
        precondition(controller.isPaused, "STOPWATCH: expected paused")
        controller.togglePause()
        precondition(!controller.isPaused, "STOPWATCH: expected resumed")

        controller.rewind()
        precondition(controller.remaining == 0, "STOPWATCH: rewind should be a no-op")

        controller.finishBlock()
        precondition(controller.phase == .breakTime, "STOPWATCH: expected breakTime after stop")
        precondition(controller.breakRemaining == 5 * 60, "STOPWATCH: expected the default 5-min break")
        precondition(controller.session?.durationMin == 1, "STOPWATCH: sub-minute block should book 1 min")

        controller.finishToWrapUp(checkIn: "stopped the clock")
        precondition(controller.phase == .wrapUp, "STOPWATCH: expected wrapUp")
        controller.completeWrapUp(completedTasks: ["stopwatch test"], otherDelivered: "", nextStep: "", energyEnd: .medium, reflection: "")

        guard case let .done(path) = controller.phase, !path.hasPrefix("ERROR") else {
            print("STOPWATCH: FAILED to write log, phase=\(controller.phase)")
            exit(1)
        }
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "<unreadable>"
        precondition(contents.contains("duration_min: 1"), "STOPWATCH: expected duration_min: 1 in log")
        precondition(contents.contains("blocks: 1"), "STOPWATCH: expected blocks: 1 in log")
        precondition(contents.contains("stopped the clock"), "STOPWATCH: expected check-in note in log")
        print("STOPWATCH: OK")
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

    /// Headless check of the Google Calendar event building (title composition,
    /// RFC3339 start/end spanning the block, busy/opaque, explicit timezone, no
    /// default reminders). Pure formatting only: no auth, no network.
    static func runCalendarTest() {
        precondition(CalendarService.eventTitle(forGoal: "") == "Loft Hours",
                     "CALENDAR: empty goal should be plain title")
        precondition(CalendarService.eventTitle(forGoal: "  ") == "Loft Hours",
                     "CALENDAR: whitespace goal should be plain title")
        precondition(CalendarService.eventTitle(forGoal: "write the report") == "Loft Hours - write the report",
                     "CALENDAR: goal should be appended after the dash")

        let start = Date(timeIntervalSince1970: 1_748_620_200)
        let body = CalendarService.eventBody(title: "Loft Hours - x", start: start, durationMin: 25, timeZone: "America/New_York")

        precondition((body["summary"] as? String) == "Loft Hours - x", "CALENDAR: summary mismatch")
        precondition((body["transparency"] as? String) == "opaque", "CALENDAR: should be busy/opaque")
        let reminders = body["reminders"] as? [String: Any]
        precondition((reminders?["useDefault"] as? Bool) == false, "CALENDAR: should suppress default reminders")

        let startObj = body["start"] as? [String: Any]
        let endObj = body["end"] as? [String: Any]
        precondition((startObj?["timeZone"] as? String) == "America/New_York", "CALENDAR: start timezone mismatch")
        precondition((endObj?["timeZone"] as? String) == "America/New_York", "CALENDAR: end timezone mismatch")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let startStr = startObj?["dateTime"] as? String
        let endStr = endObj?["dateTime"] as? String
        precondition(startStr == fmt.string(from: start), "CALENDAR: start dateTime mismatch")
        precondition(endStr == fmt.string(from: start.addingTimeInterval(25 * 60)), "CALENDAR: end should be start + 25 min")
        print("CALENDAR: OK")
    }

    /// Headless check of the home-screen welcome greeting: every template across
    /// every pool renders with the name (no leftover placeholder) and stays to a
    /// max of three words; the right pool is chosen per weekday; and the
    /// no-immediate-repeat avoidance works. No randomness assertions.
    static func runWelcomeTest() {
        let allPools: [[String]] = [
            Messages.welcomeMonday, Messages.welcomeWednesday, Messages.welcomeFriday,
            Messages.welcomeWeekend, Messages.welcomeGeneral,
        ]
        for pool in allPools {
            for template in pool {
                let rendered = template.replacingOccurrences(of: "{name}", with: "Sam")
                precondition(template.contains("{name}"), "WELCOME: template missing placeholder: \(template)")
                precondition(!rendered.contains("{name}"), "WELCOME: placeholder survived: \(template)")
                precondition(rendered.contains("Sam"), "WELCOME: name not rendered: \(template)")
                let words = rendered.split(separator: " ").count
                precondition(words <= 3, "WELCOME: over 3 words (\(words)): \(rendered)")
            }
        }

        // Pool routing by a UTC calendar on known dates (Jun 2026: 1=Mon, 3=Wed,
        // 5=Fri, 6=Sat).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd"

        func assertPool(_ dateStr: String, _ expected: [String], _ label: String) {
            let date = fmt.date(from: dateStr)!
            let result = Messages.welcome(name: "Sam", date: date, calendar: cal)
            precondition(expected.contains(result.template), "WELCOME: \(label) routed to wrong pool: \(result.template)")
        }
        assertPool("2026-06-01", Messages.welcomeMonday, "Monday")
        assertPool("2026-06-03", Messages.welcomeWednesday, "Wednesday")
        assertPool("2026-06-05", Messages.welcomeFriday, "Friday")
        assertPool("2026-06-06", Messages.welcomeWeekend, "Saturday")
        assertPool("2026-06-02", Messages.welcomeGeneral, "Tuesday")

        // No immediate repeat: avoiding a template never returns it.
        let wed = fmt.date(from: "2026-06-03")!
        for _ in 0..<20 {
            let avoid = Messages.welcomeWednesday[0]
            let r = Messages.welcome(name: "Sam", date: wed, calendar: cal, avoiding: avoid)
            precondition(r.template != avoid, "WELCOME: avoidance failed, returned \(r.template)")
        }
        print("WELCOME: OK")
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
