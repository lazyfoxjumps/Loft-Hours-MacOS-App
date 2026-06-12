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

    /// Headless check of the reminders model: trigger components per recurrence,
    /// the monthly 29-31 day clamp, next-fire and today's-occurrence math, the
    /// Codable persistence round trip, and the focus-nudge copy pool. Pure logic
    /// only: no UNUserNotificationCenter (which needs a launched app bundle).
    static func runReminderTest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd HH:mm"

        // Anchor: Friday 2026-07-31 at 15:30 (day 31 exercises the monthly clamp).
        let anchor = fmt.date(from: "2026-07-31 15:30")!

        // Once: full date components, no repeat.
        var r = Reminder(kind: .task, title: "pick up the document", anchor: anchor, recurrence: .once)
        var c = r.triggerComponents(calendar: cal)
        precondition(!r.repeats, "REMINDER: once should not repeat")
        precondition(c.year == 2026 && c.month == 7 && c.day == 31, "REMINDER: once should pin the full date")
        precondition(c.hour == 15 && c.minute == 30, "REMINDER: once time mismatch")

        // Daily: time only.
        r.recurrence = .daily
        c = r.triggerComponents(calendar: cal)
        precondition(r.repeats, "REMINDER: daily should repeat")
        precondition(c.year == nil && c.day == nil && c.weekday == nil, "REMINDER: daily should only pin the time")
        precondition(c.hour == 15 && c.minute == 30, "REMINDER: daily time mismatch")

        // Weekly: weekday + time (2026-07-31 is a Friday, weekday 6).
        r.recurrence = .weekly
        c = r.triggerComponents(calendar: cal)
        precondition(c.weekday == 6 && c.day == nil, "REMINDER: weekly should pin the weekday, not the day")

        // Monthly: day 31 clamps to 28 and gets flagged; day 15 passes through.
        r.recurrence = .monthly
        c = r.triggerComponents(calendar: cal)
        precondition(c.day == Reminder.monthlyDayCap, "REMINDER: day 31 should clamp to \(Reminder.monthlyDayCap)")
        precondition(r.monthlyDayClamped(calendar: cal), "REMINDER: day 31 should be flagged as clamped")
        let midMonth = Reminder(anchor: fmt.date(from: "2026-07-15 09:00")!, recurrence: .monthly)
        precondition(midMonth.triggerComponents(calendar: cal).day == 15, "REMINDER: day 15 should not clamp")
        precondition(!midMonth.monthlyDayClamped(calendar: cal), "REMINDER: day 15 should not be flagged")

        // Next fire: a past one-off has nothing left; daily fires at the next 15:30.
        let now = fmt.date(from: "2026-08-10 12:00")!
        let pastOnce = Reminder(anchor: anchor, recurrence: .once)
        precondition(pastOnce.nextFireDate(after: now, calendar: cal) == nil, "REMINDER: past once should have no next fire")
        let futureOnce = Reminder(anchor: fmt.date(from: "2026-08-11 09:00")!, recurrence: .once)
        precondition(futureOnce.nextFireDate(after: now, calendar: cal) == futureOnce.anchor, "REMINDER: future once should fire at its anchor")
        let daily = Reminder(anchor: anchor, recurrence: .daily)
        precondition(daily.nextFireDate(after: now, calendar: cal) == fmt.date(from: "2026-08-10 15:30"), "REMINDER: daily should fire today at 15:30")

        // Today's occurrence: daily lands today at its time; a once on another
        // day stays off the rail; weekly only shows on its weekday.
        precondition(daily.occurrenceToday(now: now, calendar: cal) == fmt.date(from: "2026-08-10 15:30"), "REMINDER: daily occurrence mismatch")
        precondition(pastOnce.occurrenceToday(now: now, calendar: cal) == nil, "REMINDER: other-day once should not occur today")
        let weekly = Reminder(anchor: anchor, recurrence: .weekly)
        precondition(weekly.occurrenceToday(now: now, calendar: cal) == nil, "REMINDER: Friday weekly should not occur on a Monday")
        let friday = fmt.date(from: "2026-08-14 12:00")!
        precondition(weekly.occurrenceToday(now: friday, calendar: cal) == fmt.date(from: "2026-08-14 15:30"), "REMINDER: weekly should occur on its weekday")

        // Custom every-2-days: anchored Fri 7-31, so it lands on even day
        // offsets. 8-10 (offset 10) fires; 8-11 (offset 11) doesn't.
        var every2 = Reminder(anchor: anchor, recurrence: .custom)
        every2.customMode = .everyNDays
        every2.customDays = 2
        let tuesday = fmt.date(from: "2026-08-11 12:00")!
        precondition(every2.occurrenceToday(now: now, calendar: cal) == fmt.date(from: "2026-08-10 15:30"), "REMINDER: every-2-days should occur on even offsets")
        precondition(every2.occurrenceToday(now: tuesday, calendar: cal) == nil, "REMINDER: every-2-days should skip odd offsets")
        precondition(every2.nextFireDate(after: now, calendar: cal) == fmt.date(from: "2026-08-10 15:30"), "REMINDER: every-2-days next fire today")
        precondition(every2.nextFireDate(after: tuesday, calendar: cal) == fmt.date(from: "2026-08-12 15:30"), "REMINDER: every-2-days next fire skips a day")
        let intervalTriggers = every2.notificationTriggers(now: now, calendar: cal)
        precondition(intervalTriggers.count == Reminder.intervalLookahead, "REMINDER: interval should schedule the full lookahead window")
        precondition(intervalTriggers.allSatisfy { !$0.repeats }, "REMINDER: interval triggers are one-shots")

        // Custom weekdays Mon/Wed/Fri: 8-10 is a Monday, 8-11 a Tuesday.
        var mwf = Reminder(anchor: anchor, recurrence: .custom)
        mwf.customMode = .weekdays
        mwf.customWeekdays = [2, 4, 6]
        precondition(mwf.occurrenceToday(now: now, calendar: cal) == fmt.date(from: "2026-08-10 15:30"), "REMINDER: MWF should occur on Monday")
        precondition(mwf.occurrenceToday(now: tuesday, calendar: cal) == nil, "REMINDER: MWF should skip Tuesday")
        precondition(mwf.nextFireDate(after: tuesday, calendar: cal) == fmt.date(from: "2026-08-12 15:30"), "REMINDER: MWF next fire from Tuesday is Wednesday")
        let weekdayTriggers = mwf.notificationTriggers(now: now, calendar: cal)
        precondition(weekdayTriggers.count == 3 && weekdayTriggers.allSatisfy(\.repeats), "REMINDER: one repeating trigger per picked weekday")
        var noDays = mwf
        noDays.customWeekdays = []
        precondition(noDays.nextFireDate(after: now, calendar: cal) == nil, "REMINDER: empty weekday set has nothing to fire")

        // Calendar mirroring: the recurrence rules Google gets.
        precondition(CalendarService.recurrenceRule(for: pastOnce, calendar: cal) == nil, "REMINDER: once has no RRULE")
        precondition(CalendarService.recurrenceRule(for: daily, calendar: cal) == "RRULE:FREQ=DAILY", "REMINDER: daily RRULE mismatch")
        precondition(CalendarService.recurrenceRule(for: weekly, calendar: cal) == "RRULE:FREQ=WEEKLY;BYDAY=FR", "REMINDER: weekly RRULE mismatch")
        precondition(CalendarService.recurrenceRule(for: every2, calendar: cal) == "RRULE:FREQ=DAILY;INTERVAL=2", "REMINDER: interval RRULE mismatch")
        precondition(CalendarService.recurrenceRule(for: mwf, calendar: cal) == "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR", "REMINDER: weekday-set RRULE mismatch")

        // Persistence round trip through the same helpers the service uses.
        let saved = [pastOnce, daily, every2, mwf, Reminder(kind: .focusNudge, anchor: anchor, recurrence: .weekly, enabled: false)]
        let restored = ReminderService.decode(ReminderService.encode(saved))
        precondition(restored == saved, "REMINDER: codable round trip mismatch")
        precondition(ReminderService.decode(nil).isEmpty, "REMINDER: nil data should decode to empty")

        // A blob saved before the custom-recurrence fields existed must still
        // decode (defaults fill in), so an upgrade never wipes saved reminders.
        let legacyJSON = """
        [{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","kind":"task","title":"wash my face","anchor":0,"recurrence":"daily","enabled":true}]
        """
        let legacy = ReminderService.decode(legacyJSON.data(using: .utf8))
        precondition(legacy.count == 1, "REMINDER: legacy blob failed to decode")
        precondition(legacy[0].title == "wash my face" && legacy[0].customDays == 2 && legacy[0].customWeekdays.isEmpty && legacy[0].calendarEventId == nil, "REMINDER: legacy defaults mismatch")

        // Focus-nudge copy pool: non-empty, and clean of em/en dashes per the
        // voice guideline.
        precondition(!Messages.focusNudges.isEmpty, "REMINDER: focus nudge pool is empty")
        for line in Messages.focusNudges {
            precondition(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "REMINDER: dash in nudge copy: \(line)")
        }
        print("REMINDER: OK")
    }

    /// Headless check of the routines feature: the schedule proxy delegating to
    /// Reminder's recurrence math, the window/active helpers, the Free (never
    /// Busy) calendar event body, the Codable round trip with a minimal-blob
    /// upgrade fixture, the per-day tracker's upsert/tick/finish/reload cycle,
    /// and the nudge copy pool. Pure logic plus temp-dir file IO; no
    /// UNUserNotificationCenter (needs a launched bundle).
    @MainActor
    static func runRoutineTest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd HH:mm"

        // A daily 45-minute morning routine anchored at 07:00.
        let anchor = fmt.date(from: "2026-07-31 07:00")!
        var morning = Routine(name: "Morning routine", emoji: "☀️", anchor: anchor, durationMin: 45, recurrence: .daily)
        morning.tasks = [
            RoutineTask(emoji: "🛏️", title: "Make the bed"),
            RoutineTask(emoji: "🪥", title: "Brush teeth"),
            RoutineTask(emoji: "☕", title: "Coffee"),
        ]
        precondition(morning.displayName == "☀️ Morning routine", "ROUTINE: displayName mismatch")
        precondition(morning.tasks[0].displayTitle == "🛏️ Make the bed", "ROUTINE: task displayTitle mismatch")

        // Schedule proxy: today's occurrence, the window span, and isActive
        // inside vs outside the window.
        let now = fmt.date(from: "2026-08-10 07:20")!
        let start = fmt.date(from: "2026-08-10 07:00")!
        precondition(morning.occurrenceToday(now: now, calendar: cal) == start, "ROUTINE: daily occurrence mismatch")
        let window = morning.windowToday(now: now, calendar: cal)
        precondition(window?.lowerBound == start, "ROUTINE: window start mismatch")
        precondition(window?.upperBound == start.addingTimeInterval(45 * 60), "ROUTINE: window should span durationMin")
        precondition(morning.isActive(now: now, calendar: cal), "ROUTINE: 07:20 should be inside the 07:00+45m window")
        precondition(!morning.isActive(now: fmt.date(from: "2026-08-10 08:00")!, calendar: cal), "ROUTINE: 08:00 should be outside the window")
        precondition(morning.scheduleDescription(calendar: cal).hasSuffix(", 45 min"), "ROUTINE: schedule description should carry the window length")

        // Recurrence variety flows through the proxy: weekday set triggers and
        // the monthly 29-31 clamp.
        var mwf = morning
        mwf.recurrence = .custom
        mwf.customMode = .weekdays
        mwf.customWeekdays = [2, 4, 6]
        precondition(mwf.notificationTriggers(now: now, calendar: cal).count == 3, "ROUTINE: one trigger per picked weekday")
        var endOfMonth = morning
        endOfMonth.anchor = fmt.date(from: "2026-07-31 21:00")!
        endOfMonth.recurrence = .monthly
        precondition(endOfMonth.monthlyDayClamped(calendar: cal), "ROUTINE: day 31 should be flagged as clamped")

        // Calendar mirroring: the event spans the full window, recurs with the
        // schedule, and is always Free (transparent), never Busy.
        let body = CalendarService.routineEventBody(morning, start: start, timeZone: "UTC", calendar: cal)
        precondition(body["transparency"] as? String == "transparent", "ROUTINE: calendar event must be Free, not Busy")
        precondition((body["recurrence"] as? [String])?.first == "RRULE:FREQ=DAILY", "ROUTINE: daily RRULE mismatch")
        precondition(body["summary"] as? String == "Loft Hours - ☀️ Morning routine", "ROUTINE: event title mismatch")
        let iso = ISO8601DateFormatter()
        if let s = (body["start"] as? [String: String])?["dateTime"].flatMap(iso.date(from:)),
           let e = (body["end"] as? [String: String])?["dateTime"].flatMap(iso.date(from:)) {
            precondition(e.timeIntervalSince(s) == 45 * 60, "ROUTINE: event should span the window")
        } else {
            preconditionFailure("ROUTINE: event body missing start/end")
        }
        var once = morning
        once.recurrence = .once
        precondition(CalendarService.routineEventBody(once, start: start, timeZone: "UTC", calendar: cal)["recurrence"] == nil, "ROUTINE: once should have no RRULE")

        // Persistence round trip through the same helpers the service uses.
        let saved = [morning, mwf, endOfMonth]
        let restored = RoutineService.decode(RoutineService.encode(saved))
        precondition(restored == saved, "ROUTINE: codable round trip mismatch")
        precondition(RoutineService.decode(nil).isEmpty, "ROUTINE: nil data should decode to empty")

        // A minimal blob (as if saved by an older build before optional fields
        // existed) must still decode with defaults filling in.
        let legacyJSON = """
        [{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Night routine","anchor":0}]
        """
        let legacy = RoutineService.decode(legacyJSON.data(using: .utf8))
        precondition(legacy.count == 1, "ROUTINE: legacy blob failed to decode")
        precondition(legacy[0].name == "Night routine" && legacy[0].durationMin == 30
                        && legacy[0].recurrence == .daily && legacy[0].notify && legacy[0].tasks.isEmpty,
                     "ROUTINE: legacy defaults mismatch")

        // Tracker: start, tick, persist on every mutation, reload from disk,
        // finish, per-day reads, and the activity counts the calendar uses.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lofthours-routine-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
        let cfg = AppConfig(logDirectory: tmp)
        let tracker = RoutineTracker(config: cfg, calendar: cal)

        tracker.recordStart(morning, now: now)
        tracker.setTask(morning.tasks[0].id, done: true, routineId: morning.id, now: now)
        tracker.setTask(morning.tasks[1].id, done: true, routineId: morning.id, now: now)
        tracker.setTask(morning.tasks[1].id, done: false, routineId: morning.id, now: now)

        // A second instance reading the same file sees the ticks: crash safety.
        let reloaded = RoutineTracker(config: cfg, calendar: cal)
        var entry = reloaded.entryToday(for: morning.id, now: now)
        precondition(entry?.doneTaskIds == [morning.tasks[0].id], "ROUTINE: tracker reload lost the ticks")
        precondition(entry?.totalTasks == 3 && entry?.finishedAt == nil, "ROUTINE: in-progress entry mismatch")
        precondition(entry?.progressText == "1/3 tasks", "ROUTINE: progress text mismatch")

        // Re-starting the same routine the same day resumes (upsert, ticks
        // kept); a renamed routine refreshes the denormalized fields.
        var renamed = morning
        renamed.name = "Slow morning"
        reloaded.recordStart(renamed, now: now.addingTimeInterval(60))
        entry = reloaded.entryToday(for: morning.id, now: now)
        precondition(entry?.doneTaskIds == [morning.tasks[0].id] && entry?.name == "Slow morning", "ROUTINE: upsert should keep ticks and refresh the name")

        reloaded.recordFinish(morning.id, now: now.addingTimeInterval(120))
        precondition(reloaded.entryToday(for: morning.id, now: now)?.finishedAt != nil, "ROUTINE: finish not recorded")
        precondition(reloaded.entries(on: now).count == 1, "ROUTINE: expected one entry today")
        precondition(reloaded.entries(on: fmt.date(from: "2026-08-09 12:00")!).isEmpty, "ROUTINE: yesterday should be empty")

        // Activity counts key by start of day; an untouched run doesn't count.
        var untouched = Routine(name: "Night routine", emoji: "🌙", anchor: anchor, durationMin: 30, recurrence: .daily)
        untouched.tasks = [RoutineTask(title: "Wind down")]
        reloaded.recordStart(untouched, now: now)
        let counts = reloaded.activityCounts()
        precondition(counts[cal.startOfDay(for: now)] == 1, "ROUTINE: activity count mismatch (untouched runs shouldn't count)")
        precondition(RoutineTracker.dayKey(now, calendar: cal) == "2026-08-10", "ROUTINE: day key mismatch")

        // Nudge pool: non-empty, fresh lines, clean of em/en dashes per the
        // voice guideline; same for the all-ticked caption.
        precondition(!Messages.routineNudges.isEmpty, "ROUTINE: nudge pool is empty")
        for line in Messages.routineNudges + [Messages.routineAllDone] {
            precondition(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "ROUTINE: dash in copy: \(line)")
        }
        print("ROUTINE: OK")
    }

    /// Headless check of the Review > Logs calendar math: the activity-count to
    /// intensity-opacity bucketing (0 = no circle, then four steps capping at
    /// 4+), and the merge of session-log day counts with routine activity counts
    /// into one per-day total the grid draws from.
    static func runCalendarGridTest() {
        precondition(LogCalendarView.intensityOpacity(for: 0) == 0, "CALGRID: 0 activity should have no circle")
        precondition(LogCalendarView.intensityOpacity(for: 1) == 0.20, "CALGRID: step 1 mismatch")
        precondition(LogCalendarView.intensityOpacity(for: 2) == 0.40, "CALGRID: step 2 mismatch")
        precondition(LogCalendarView.intensityOpacity(for: 3) == 0.65, "CALGRID: step 3 mismatch")
        precondition(LogCalendarView.intensityOpacity(for: 4) == 0.90, "CALGRID: step 4 mismatch")
        precondition(LogCalendarView.intensityOpacity(for: 12) == 0.90, "CALGRID: 4+ should cap at the top step")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd HH:mm"

        let d1 = cal.startOfDay(for: fmt.date(from: "2026-06-10 09:00")!)
        let d2 = cal.startOfDay(for: fmt.date(from: "2026-06-11 09:00")!)
        let d3 = cal.startOfDay(for: fmt.date(from: "2026-06-12 09:00")!)

        func log(_ stamp: String) -> ParsedLog {
            ParsedLog(url: URL(fileURLWithPath: "/tmp/\(stamp.replacingOccurrences(of: " ", with: "_")).md"),
                      startedAt: fmt.date(from: stamp)!, endedAt: nil, durationMin: 25, blocks: 1,
                      goal: "g", delivered: "", energyStart: .medium, energyEnd: .medium,
                      nextStep: "", reflection: "")
        }
        // Two sessions on d1, one on d2, none on d3.
        let logs = [log("2026-06-10 09:00"), log("2026-06-10 14:00"), log("2026-06-11 09:00")]
        // Routines: one completed on d1, two on d3.
        let routineCounts: [Date: Int] = [d1: 1, d3: 2]

        let counts = LogCalendarView.dayCounts(logs: logs, routineCounts: routineCounts, calendar: cal)
        precondition(counts[d1] == 3, "CALGRID: d1 should sum 2 sessions + 1 routine, got \(counts[d1] ?? -1)")
        precondition(counts[d2] == 1, "CALGRID: d2 should be 1 session, got \(counts[d2] ?? -1)")
        precondition(counts[d3] == 2, "CALGRID: d3 should be 2 routines, got \(counts[d3] ?? -1)")
        print("CALGRID: OK")
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
