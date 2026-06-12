import Foundation

/// Central home for the app's spoken-to-you copy: the encouraging lines that
/// cycle on notification pop-ups and the body-care nudges under the break timer.
///
/// Voice: a study-with-me friend who's quietly in the room with you, warm and
/// casual, gently holding you accountable. See `docs/VOICE-AND-TONE.md`. Keep
/// every line short enough to read at a glance, second-person, and free of
/// em/en dashes (commas, colons, and parens only).
enum Messages {
    /// Fired when a focus block ends and the break begins.
    static let blockComplete = [
        "That's a block done. Proud of you. Go stretch.",
        "Block in the bag. Take your break, you earned it.",
        "One block down. Breathe, hydrate, come on back.",
        "You showed up and did the thing. Break time.",
        "Nice work in there. Step away for a sec, I've got the timer.",
    ]

    /// Fired at the halfway point of a focus block.
    static let halfway = [
        "Halfway there. You're doing great, keep going.",
        "Right in the middle of it. Stay with me.",
        "Halfway mark. Look at you go.",
        "You're cruising. Half done already.",
    ]

    /// Fired in the final minute of a focus block.
    static let lastMinute = [
        "About a minute left. Land the thought, don't start a new one.",
        "Final minute. Bring it in for a soft landing.",
        "Almost there, roughly a minute. You've got this.",
        "One minute to go. Wrap up where you are, no rush.",
    ]

    /// Fired when the break timer runs out.
    static let breakOver = [
        "Break's done. Ready when you are, no pressure.",
        "That's the break. Come back when you're set, I saved your spot.",
        "Rest's over. Let's pick it back up together.",
        "Whenever you're ready, I'm right here.",
    ]

    /// Rotating body-care nudges shown under the break timer.
    static let breakReminders = [
        "Drink some water, seriously.",
        "Stand up and give those legs a stretch.",
        "Look at something far away for twenty seconds, your eyes will thank you.",
        "Roll your shoulders back and unclench that jaw.",
        "Take a couple slow breaths. In, and out.",
        "Rest your eyes for a sec, you've been staring.",
        "Sip some water and wiggle your fingers loose.",
    ]

    /// Bodies for the recurring "time to focus" reminder notifications. A fresh
    /// line is picked each time a nudge is scheduled (and re-rolled at every
    /// launch), so the same reminder doesn't sound like a broken record.
    static let focusNudges = [
        "It's focus time. The loft is open whenever you are.",
        "Your focus block is calling. Come settle in.",
        "Time to get a block in. I'll hold the timer.",
        "This is your nudge: pick one thing and let's go.",
        "The desk is ready. Come do a block with me.",
        "Hey, it's that time. Let's make some quiet progress.",
    ]

    /// Bodies for routine start notifications. Generic on purpose so the same
    /// pool fits a morning routine, a night routine, or anything in between;
    /// the notification title already carries the routine's own name. A fresh
    /// line is picked at scheduling time and re-rolled at every launch, so the
    /// same routine doesn't sound like a broken record.
    static let routineNudges = [
        "It's that time again. Ease into the first step.",
        "Your routine window just opened. No rush, just start.",
        "Same time, same you. Let's run through it together.",
        "The loft is ready when you are. One small step to begin.",
        "Time to do the thing. You know the one.",
        "Little steps, every time. The first one is waiting.",
        "Right on schedule. Tick one box and the rest will follow.",
        "Your future self asked for this one. Let's not keep them waiting.",
    ]

    /// Caption under the finish button on the routine timer once every task is
    /// ticked. Invitation, not pressure: nothing auto-closes.
    static let routineAllDone = "That's the whole list. Finish up whenever you're ready."

    // MARK: - Home-screen welcome greeting

    /// Cycling greeting that replaces the "Loft Hours" wordmark on the home
    /// screen, personalized with the user's name. Every line carries the `{name}`
    /// placeholder and stays to a maximum of three words (name included). Some
    /// days get their own pool (Monday's fresh-week push, a gentle midweek
    /// steadier, Friday's near-weekend lift, a slower weekend); the rest of the
    /// week draws from the general pool. See `docs/VOICE-AND-TONE.md`.

    static let welcomeMonday = [
        "New week, {name}!",
        "Fresh start, {name}.",
        "Onward, {name}!",
        "Let's begin, {name}.",
        "Week one, {name}.",
        "Clean slate, {name}.",
        "Let's roll, {name}.",
        "Monday momentum, {name}.",
    ]

    /// Midweek, encouraging without the on-the-nose "hump day" line.
    static let welcomeWednesday = [
        "Midweek, {name}.",
        "Steady on, {name}.",
        "Keep going, {name}.",
        "Halfway in, {name}.",
        "Hold steady, {name}.",
        "Pace yourself, {name}.",
        "Cresting it, {name}.",
        "Downhill soon, {name}.",
    ]

    static let welcomeFriday = [
        "Finally Friday, {name}!",
        "TGIF, {name}!",
        "Friyay, {name}!",
        "Almost weekend, {name}!",
        "Home stretch, {name}.",
        "Last push, {name}!",
        "Nearly there, {name}.",
        "So close, {name}.",
    ]

    /// Saturday and Sunday: slower, softer, permission to rest.
    static let welcomeWeekend = [
        "Breathe, {name}.",
        "Rest up, {name}.",
        "Slow down, {name}.",
        "Weekend mode, {name}.",
        "Easy now, {name}.",
        "No rush, {name}.",
        "Take five, {name}.",
        "Unwind, {name}.",
    ]

    /// Tuesday, Thursday, and the fallback for any day.
    static let welcomeGeneral = [
        "Welcome back, {name}.",
        "Hey, {name}.",
        "Let's go, {name}!",
        "Hello, {name}.",
        "Ready, {name}?",
        "Let's focus, {name}.",
        "You're here, {name}.",
        "Hi again, {name}.",
        "Welcome, {name}!",
    ]

    /// The welcome pool for a `Calendar` weekday (1 = Sunday ... 7 = Saturday).
    static func welcomePool(forWeekday weekday: Int) -> [String] {
        switch weekday {
        case 1, 7: return welcomeWeekend   // Sun, Sat
        case 2:    return welcomeMonday
        case 4:    return welcomeWednesday
        case 6:    return welcomeFriday
        default:   return welcomeGeneral   // Tue, Thu
        }
    }

    /// Pick a greeting for `name` on `date`, avoiding `avoiding` (the last
    /// template shown) so it never repeats back to back. Returns the raw
    /// template (store this to feed `avoiding` next time) and the rendered line.
    static func welcome(
        name: String,
        date: Date,
        calendar: Calendar = .current,
        avoiding: String? = nil
    ) -> (template: String, text: String) {
        let weekday = calendar.component(.weekday, from: date)
        var pool = welcomePool(forWeekday: weekday)
        if let avoiding, pool.count > 1 {
            pool.removeAll { $0 == avoiding }
        }
        let template = pool.randomElement() ?? "Welcome, {name}!"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = template.replacingOccurrences(of: "{name}", with: trimmed)
        return (template, text)
    }
}

extension Array where Element == String {
    /// A random line from the pool, for the cues that should feel fresh each
    /// time. Falls back to an empty string only if the pool is empty (it never
    /// is), so callers stay non-optional.
    func pick() -> String { randomElement() ?? "" }
}
