<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <img src="docs/logo.svg" alt="Loft Hours" width="280">
  </picture>
</p>

<h1 align="center">Loft Hours</h1>

<p align="center">
  A quiet little focus app for ADHD and neurodivergent brains.<br>
  Like having a friend up in the loft with you for a "study with me" session, minus the small talk.
</p>

---

## Hey, what is this?

Loft Hours is a **simple Mac app that helps you actually start (and finish) your work.**

You know that thing where you *want* to focus, you have stuff to do, but you just... can't get your brain to begin? And when you finally do, you blink and three hours are gone and you have no idea if you got anything done?

Loft Hours is built for exactly that. It's a digital **body double**, that "someone's-here-working-with-me" feeling that makes focusing way easier for a lot of ADHD and neurodivergent folks, packed into one small, calm app.

It does **not** nag you. It does **not** gamify your life with streaks and confetti and guilt. It quietly sets up your work session, stays out of your way while you work, and then shows you the receipts of what you actually did. That's it.

> **Heads up:** this is a **beta** (version 0.9.0). It works, your friends can use it, but a few rough edges are expected. See [Known issues](#known-issues-beta-stuff) below.

---

## Why this helps ADHD / neurodivergent brains

Regular productivity apps assume the hard part is *remembering* your tasks. For a lot of us, the hard part is **starting**, **staying**, and **believing we did anything**. Loft Hours is designed around those three:

| The struggle | How Loft Hours helps |
|---|---|
| 🚀 **Can't start** ("task paralysis") | A short, friendly setup asks what you're doing and what "done" looks like, so the mountain becomes one clear step. |
| 👥 **Focus feels impossible alone** | **Body doubling.** A visible timer ring + a calm "we're in a session now" mode gives you that someone's-here-with-me push, without an actual person watching. |
| 🌪️ **Too many distractions** | One click can flip on Do Not Disturb and close your distracting apps, so you don't have to white-knuckle your own willpower. |
| ⏰ **Time blindness** | The timer shows you exactly where you are in the block, with gentle chimes at the halfway point and the final minute. No surprise time-jumps. |
| 🧠 **"I did nothing today" brain** | At the end you check off what you finished, and it gets saved. Later, weekly/monthly reviews show you proof of your effort, including the invisible stuff. |

The whole vibe: **gentle structure, zero shame.**

---

## What a session actually looks like

1. **Tell it what you're working on.** Add one task or a little list ("Today I'm working on... and also..."). Pick how long you want to go (25, 50, 90 minutes, or your own number).
2. **Decide what "done" looks like.** One concrete thing that'll feel finished. This is the secret sauce, it turns "ugh, homework" into "answer questions 1 to 5."
3. **Set the room (optional).** Want Loft Hours to flip on Do Not Disturb and close Slack/Twitter/whatever for you? Say the word. Don't want that? Skip it. Totally up to you.
4. **Work.** A clean focus timer appears. The app goes quiet and lets you cook. Soft chimes mark the halfway point and the last minute.
5. **Take your break.** When the block ends, it checks in: "How's it going?" You can log a note or just breathe.
6. **Wrap up.** Tick off what you finished, and add as many extra "Other" things you did as you want. Loft Hours saves a tidy little log of the session to your computer.
7. **Go again or call it.** Start another block, or finish for the day.

---

## Features

- 🎯 **Multi-task intake** — line up everything you want to tackle, not just one thing.
- ⭕ **Visual focus timer** — a calm circular countdown so you always know where you are in the block.
- 🔕 **Do Not Disturb toggle** — flip your Mac's Focus mode on/off right from the app (one-time setup, see [below](#optional-do-not-disturb--focus-setup)). If you haven't set it up yet, the home screen gently points you to it instead of failing silently.
- 🚪 **App wrangling** — auto-close the apps that distract you when a session starts, and reopen them after if you want.
- ☕ **Break check-ins** — a rotating mix of encouragement and gentle body-care reminders (drink water, stretch, rest your eyes) between blocks, never naggy.
- ✅ **Done-checklist wrap-up** — check off what you finished, and add as many extra "Other" things you did as you want.
- 📝 **Automatic session logs** — every session is saved as a plain Markdown file in `~/Documents/study-log/`. They're yours, readable in any text app, forever.
- 📊 **Weekly & monthly reviews** — see your focused hours, your streak, when you do your best work, and patterns you'd never notice on your own.
- 🎨 **Themes** — opens in a warm **Light Academia** look, with five more cozy palettes a click away (Dark Academia, Forest Cottagecore, Candlelit Nocturne, Linen & Latte, and Classic Midnight).
- 💾 **Crash-safe + resume** — if your Mac sleeps or quits mid-session, Loft Hours picks up where you left off and can pre-fill your next session from last time.

> Your data stays on your machine. There's no account, no cloud, no tracking, no internet required. The logs are just Markdown files you own.

---

## Installing Loft Hours

### What you need
- A Mac running **macOS 14 (Sonoma) or newer**
- An **Apple Silicon Mac** (M1, M2, M3, or M4). This beta does **not** run on older Intel Macs.

### Steps
1. Go to the [**Releases**](../../releases) page and download the latest `Loft-Hours-0.9.0-beta.dmg`.
2. Double-click the downloaded `.dmg` to open it.
3. **Drag the Loft Hours icon onto the Applications folder** in the window that pops up.
4. Open your **Applications** folder and try to launch Loft Hours.

If it opens, you're done! 🎉 If macOS throws up a scary warning instead, that's expected, keep reading. 👇

---

## "Apple won't let me open it!" (the Gatekeeper bit)

Don't worry, the app is fine. This warning shows up because Loft Hours is an indie beta that hasn't paid Apple's $99/year "notarization" fee yet. macOS is cautious about apps it doesn't recognize, so it puts up a gate the **first time only**. Here's how to get through it.

### The easy way (most Macs)
1. Open your **Applications** folder.
2. **Right-click** (or Control-click) the **Loft Hours** icon.
3. Choose **Open** from the menu.
4. A dialog appears, this time with an **Open** button. Click it.

That's it. From now on it opens normally, like any other app.

### If you don't see an "Open" option (macOS 15 Sequoia and newer)
Apple changed this in the newest macOS, so do this instead:
1. Try to open Loft Hours once (let it get blocked).
2. Open **System Settings → Privacy & Security**.
3. Scroll to the bottom. You'll see a message like *"Loft Hours was blocked."* Click **Open Anyway** next to it.
4. Confirm, then launch Loft Hours again. Done.

### For the terminal-comfortable
If you'd rather just clear the flag in one command:
```bash
xattr -dr com.apple.quarantine "/Applications/Loft Hours.app"
```
Then open the app normally. (No idea what a terminal is? Totally fine, use one of the click-based methods above.)

---

## Optional: Do Not Disturb / Focus setup

The DND toggle works by running a little macOS **Shortcut** (Apple doesn't let apps flip Focus mode directly). Good news: **you don't have to build anything by hand.** Loft Hours can install the ready-made shortcuts for you in one click. (If you ever flip the toggle before this is set up, the home screen will show a little reminder pointing you right here.)

1. Open Loft Hours and click the **gear (Settings)** icon.
2. Go to the **Environment** tab.
3. Turn on the **Do Not Disturb** toggle, then click **Install shortcuts**.
4. The Shortcuts app pops up to confirm the import, click through it, and you'll see a "Focus shortcuts installed" ✅ checkmark back in Settings.

That's it, the DND toggle now works. Don't want any of this? Just leave the toggle off, everything else works fine without it.

> Prefer your own shortcuts? Open **Advanced: shortcut names** in that same section and point Loft Hours at any shortcuts you've made yourself.

> **Small honesty note:** the DND switch remembers the *last command it sent*, not your Mac's true Focus state. If you change Focus from Control Center or your iPhone, the switch might look out of sync. That's a macOS limitation, not a bug, every app that does this has it.

---

## Known issues (beta stuff)

- 🖼️ The app icon may show up **blank** on the left side of notifications. Cosmetic only, fixed once the app gets signed. Sounds and chimes work regardless.
- 🔔 Notification permission **may not stick** between launches on this unsigned build. Also a signing thing, coming in a later release.
- 💻 **Apple Silicon only** for now. Intel support can be added if a tester needs it.

Found something else? [Open an issue](../../issues), it really helps.

---

## A quick note on privacy

Loft Hours runs entirely on your Mac. No sign-up, no servers, no analytics, nothing leaves your computer. Your session logs are plain Markdown files in `~/Documents/study-log/` that you can read, edit, back up, or delete anytime.

---

## License

Loft Hours is **free to download and use** for your own personal focus sessions. The app and its source code are **All Rights Reserved**, see [LICENSE](LICENSE). Short version: enjoy the app all you want, but the code stays mine, no copying, modifying, redistributing, or selling it without permission.

---

<p align="center">
  Made with care for brains that work a little differently. 💛<br>
  Now go have a good Loft Hour.
</p>
