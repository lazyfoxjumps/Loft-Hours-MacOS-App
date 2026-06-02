# Loft Hours — Voice & Tone

The one-line version: **Loft Hours talks like the friend who's studying in the room with you.** Not a coach barking reps, not a productivity app gamifying your dopamine. A calm, warm presence that's quietly proud of you and gently keeps you honest.

This doc governs every word of in-app copy: labels, buttons, placeholders, notifications, break nudges, settings text, empty states, error messages. When you write or change a string, it should sound like it came from the same person.

---

## Who's talking

Picture the best version of a "study with me" stream or a body-doubling Discord call. Someone who:

- Sat down to work *with* you, so you're in it together.
- Celebrates the small wins without making it a big production.
- Reminds you to drink water because they actually care, not because a checklist told them to.
- Holds you accountable softly: never shame, never pressure, just a nudge and a "you've got this."

You are a peer, not an authority. You're beside the user, not above them.

## The four pillars

1. **Friendly** — Warm, human, never clinical. Contractions always (you're, let's, that's). Talk *to* one person.
2. **Encouraging** — Catch people doing well. Lead with the win. Assume the best of them, even on a rough session.
3. **Casual** — Plain, everyday words. A little playful. Short sentences. It should read like a text from a friend, not a system dialog.
4. **Personal** — Second person, present tense, in the moment. "You", "let's", "we". The app is a companion, not a tool reporting status.

## How it sounds (do / don't)

| Don't (flat, app-y) | Do (Loft Hours) |
| --- | --- |
| "Session started." | "Alright, we're in. Let's go." |
| "Block complete. Take a breath." | "That's a block done. Proud of you. Go stretch." |
| "Enter your goal." | "Hey, what are you working on today?" |
| "Halfway point reached." | "Halfway there. You're doing great, keep going." |
| "No active session." | "Nothing going right now. Ready when you are." |
| "Failed to save log." | "Hmm, I couldn't save that one. Let's try again." |
| "Reopen closed apps after wrap-up." | "Bring my apps back when we're done." |

## Rules of thumb

- **Lead with the win, then the nudge.** "Nice work in there. Now go stretch."
- **Encourage, never pressure.** "No rush", "whenever you're ready", "no pressure" are your friends. Never guilt-trip a short session or a skipped goal.
- **Short beats complete.** If a line can lose words and keep its warmth, cut them. Notifications especially: read-at-a-glance.
- **Talk like a person, not a feature.** "I saved your spot" over "Session state persisted."
- **First person is fine, sparingly.** The app can say "I've got the timer" / "I saved your spot." Use it to feel present, not chatty.
- **Questions, not commands, at intake.** "What are you working on?" not "Enter your task."
- **Celebrate effort, not just output.** Showing up counts. "You showed up and did the thing."

## Hard constraints

- **No em dashes or en dashes.** Ever. Use commas, colons, parentheses, or a second sentence. (This is a standing rule across everything in this project.)
- **No corporate filler.** Kill "please note", "in order to", "successfully", "utilize", "your session has been".
- **No fake hype.** No exclamation-point confetti on every line, no "AMAZING JOB!!!", no streak-shame. Quiet pride, not a slot machine.
- **No jargon.** "Focus block", "break", "wrap up" are fine (they're the app's own plain words). Avoid anything that needs explaining.
- **Don't overdo the pet names or bits.** Warmth comes from tone, not from stuffing "buddy" into every line.

## Where the cycling copy lives

The encouraging lines that rotate on notifications and under the break timer live in [`Sources/LoftHours/Models/Messages.swift`](../Sources/LoftHours/Models/Messages.swift). Add to those pools rather than hardcoding new strings, and keep each new line inside this voice.

When in doubt, read the line out loud. If you wouldn't say it to a friend sitting next to you, rewrite it.
