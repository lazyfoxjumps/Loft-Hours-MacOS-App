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
}

extension Array where Element == String {
    /// A random line from the pool, for the cues that should feel fresh each
    /// time. Falls back to an empty string only if the pool is empty (it never
    /// is), so callers stay non-optional.
    func pick() -> String { randomElement() ?? "" }
}
