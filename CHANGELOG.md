# Changelog

All notable changes to Loft Hours are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-02

Loft Hours graduates from beta to 1.0.

### Added
- Personalized welcome: tell Loft Hours your name once on first launch and the home screen greets you with a short rotating hello that shifts with the day (a nudge into the week on Monday, a lift toward Friday, something slower on the weekend). Editable anytime in Settings.
- Optional Google Calendar blocking: connect your Google account once and each focus block drops a "busy" event on your calendar for the length of the timer, titled "Loft Hours - your tasks". Finished blocks stay put. Fully opt-in; leave it off and the app stays entirely offline.

## [0.9.1-beta] - 2026-06-02

A refinement pass on the beta. Same app, friendlier and more polished.

### Added
- Rotating break nudges: encouragement plus gentle body-care reminders (water, stretch, rest your eyes) instead of the same line every time.
- Multiple "Other" rows at wrap-up, so you can log as many extra things you got done as you want.
- Home-screen heads-up when your Do Not Disturb shortcut isn't installed yet, so the toggle never fails silently.

### Changed
- Light Academia is the new default theme (existing users keep whatever they had).
- Linen & Latte was recolored so it no longer reads as a near-twin of Light Academia.
- Friendlier voice throughout the app, like a study-with-me friend quietly in the room with you.
- Focus notifications are now marked time-sensitive (takes full effect once the app is signed).

## [0.9.0-beta] - 2026-06-01

The first public beta: a "study with me" focus app for ADHD and neurodivergent brains. It quietly sets up your work session, stays out of your way while you focus, then shows you the receipts of what you actually got done. No nagging, no streak guilt.

### Added
- The full focus loop: multi-task intake, the circular focus ring timer, break check-ins, a done-checklist wrap-up, and Markdown session logs in `~/Documents/study-log/`.
- Weekly and monthly review rollups.
- Do Not Disturb via one-click bundled Shortcuts, plus opt-in app management (close distractions on start, reopen on finish).
- Theming with a Classic Midnight default plus academia presets, live-switchable.
- Synced in-app chimes and native notifications.

### Known limitations
- Apple Silicon only (M1/M2/M3/M4); does not run on Intel.
- Un-notarized, so macOS gates the first launch once (right-click, Open).
- On the unsigned build the notification icon may render blank and notification permission may not persist between launches. Chimes work regardless.

[1.0.0]: https://github.com/lazyfoxjumps/Loft-Hours-MacOS-App/releases/tag/v1.0.0
[0.9.1-beta]: https://github.com/lazyfoxjumps/Loft-Hours-MacOS-App/releases/tag/v0.9.1-beta
[0.9.0-beta]: https://github.com/lazyfoxjumps/Loft-Hours-MacOS-App/releases/tag/v0.9.0-beta
