# Loft Hours - Google Calendar Integration Plan

**Date:** 2026-06-02
**Status:** ✅ Core feature BUILT and working end to end (2026-06-02). Verified: real focus block creates a busy event on the connected Google Calendar with the right title and duration. Remaining: distribution/verification gating (§8), build-time-injection of the client ID is optional now (see status note).
**Scope:** Opt-in Google Calendar sync. When enabled, each focus block creates a "busy" event on the user's Google Calendar for the block's duration, titled `Loft Hours - <tasks>`. Events are never auto-deleted.

## What shipped (2026-06-02) and what changed from this plan

- **OAuth client type: iOS, not Desktop.** A Desktop client rejects custom URI scheme redirects (`redirect_uri_mismatch`); only iOS-type clients support them (and auto-register the reversed-client-ID redirect). Switched to an **iOS** client (bundle id `com.lazyfox.lofthours`).
- **No client secret.** iOS clients are PKCE-only. This means the whole "keep the secret out of the public repo" problem (§3.3 below) **evaporated** — there is no secret in source. The client ID is the only credential and it is not sensitive.
- **Scope: `calendar.events`, NOT `calendar.app.created`.** The narrower `calendar.app.created` only reaches calendars the app itself creates, so it cannot write to `primary` (this caused a silent no-event bug). `calendar.events` is the correct minimum.
- **Concurrency gotcha fixed.** The `ASWebAuthenticationSession` completion handler must be explicitly `@Sendable`; otherwise Swift infers it `@MainActor` (it's in a `@MainActor` type) and the Swift 6 runtime traps (`_dispatch_assert_queue_fail`) when AuthenticationServices invokes it off-main.
- **Files added:** `Services/GoogleAuth.swift` (PKCE + ASWebAuthenticationSession + Keychain token store + refresh/revoke), `Services/CalendarService.swift` (event create + pure testable `eventTitle`/`eventBody` helpers).
- **Files edited:** `ConfigStore` (calendarSyncEnabled/calendarId/calendarConnectedEmail), `SessionController` (`logBlockToCalendar` from `startFocusBlock`, shared `GoogleAuth`), `LoftHoursApp` (shared `GoogleAuth` env object), `SettingsPanel` (connect/disconnect + sync toggle), `LoftHours.entitlements` (network.client), `SelfTest`/`EntryPoint` (`runCalendarTest`, `CALENDAR: OK`).
- **Diagnostic test button was added then removed** after verification (it littered the calendar). `CalendarService.send` still returns a rich `CalendarSendResult` if a status surface is wanted later.

---

## 1. Behavior spec (source of truth)

- **Opt-in only.** Off by default, same as every other Phase 3 integration. User connects their Google account once in Settings.
- **One event per focus block.** Not per session. A session with 3 blocks creates 3 events.
- **Event window = the chosen timer length.** `start = block start time`, `end = start + plannedMinutes`. We do NOT track live overruns/rewinds in v1 (see §7 for the optional patch-on-finish refinement).
- **Title:** `Loft Hours - <tasks joined>`. Reuse `Session.goal` (the joined task list) so the calendar title matches the intake. Empty task list -> just `Loft Hours`.
- **Busy / opaque.** `transparency = "opaque"` so it blocks the slot and shows as busy to anyone checking the user's availability.
- **Multi-block:** when the user taps "Start another block" at the break, a new event is created for the new block.
- **Never delete.** Finishing, wrapping up, or resetting the session leaves all created events in place. No teardown call touches the calendar. This is the deliberate asymmetry vs DND/app-management (which DO tear down).
- **Best-effort, non-blocking.** A calendar failure (offline, token expired, API hiccup) never blocks or delays the timer. Matches the "environment steps never break the session" rule. Difference: because this is networked + outbound, we surface a quiet status (last-sync indicator) instead of being fully silent, so an opted-in user isn't left guessing.

---

## 2. Architecture overview (mirrors existing patterns)

| New piece | Mirrors | Responsibility |
|---|---|---|
| `Services/GoogleAuth.swift` | (new) | OAuth 2.0 PKCE flow, token refresh, Keychain storage, connect/disconnect. |
| `Services/CalendarService.swift` | `FocusService.swift` | Thin API client: `createBlockEvent(title:start:durationMin:)`. Silent/best-effort. |
| `State/ConfigStore.swift` additions | existing toggles | `calendarSyncEnabled`, `calendarId` (default `"primary"`), connection state mirror. |
| `Views/SettingsPanel.swift` additions | Environment tab | Connect/Disconnect Google, sync toggle, optional calendar picker, status line. |
| `SessionController` hook | `setupEnvironment()` | New `logBlockToCalendar()` called from `startFocusBlock()`. |
| Entitlements | `LoftHours.entitlements` | `com.apple.security.network.client`; custom URL scheme. |

Keep the same shape as `FocusService`: a small `struct`/service with silent failure, instantiated where needed from `config` values.

---

## 3. OAuth: the hard part

Google Calendar is a **sensitive scope**. There is no backend, so this is the OAuth 2.0 "installed/desktop app" flow with **PKCE**. Key decisions:

### 3.1 Redirect strategy - custom URI scheme, NOT loopback
Two options for the redirect:
- **Loopback (`http://127.0.0.1:<port>`)** - requires the app to listen on a local socket, which needs `com.apple.security.network.server` under the App Store sandbox. Avoid.
- **Custom URI scheme (`com.lofthours.app:/oauth2redirect`)** - registered via `CFBundleURLTypes` in `Info.plist`, handled by the app's `onOpenURL` / `application(_:open:)`. **No server entitlement.** This is the sandbox-friendly path and the one we use.

Register the scheme, open the system browser (`ASWebAuthenticationSession` is the right primitive on macOS - it gives a proper auth sheet, handles the callback, and is App Store friendly), exchange the auth code + PKCE verifier for tokens.

> Prefer `ASWebAuthenticationSession` (AuthenticationServices) over hand-rolling the browser bounce. It manages the callback scheme for us and is the Apple-blessed flow.

### 3.2 Scope - request the narrowest
- First choice: **`https://www.googleapis.com/auth/calendar.events.owned`** or **`calendar.app.created`** (events created by this app only). Strongest privacy story - we literally cannot read the user's other events. Confirm current scope availability when implementing.
- Fallback: **`https://www.googleapis.com/auth/calendar.events`** (manage events, can't read calendar settings/ACLs).
- Never request full `auth/calendar`.

The narrow scope also matters for §8 (Google verification) and for the App Store privacy nutrition label.

### 3.3 Client credentials
- Create an OAuth client of type **Desktop app** (or iOS/macOS) in Google Cloud Console.
- The "client secret" for a desktop client is **not actually confidential** - PKCE is what secures the flow. Ship the client ID (and the non-secret desktop secret if the chosen client type still issues one) in the app. Do not pretend it's a secret.

### 3.4 Token storage
- Store **refresh token + access token + expiry** in the **Keychain** (`kSecClassGenericPassword`, service `com.lofthours.google`). Not UserDefaults.
- `GoogleAuth.accessToken()` returns a valid token, transparently refreshing via the refresh token when expired (`grant_type=refresh_token`).
- Disconnect = revoke (`https://oauth2.googleapis.com/revoke`) + wipe Keychain + flip `calendarSyncEnabled` off.

---

## 4. CalendarService (the API call)

Single responsibility, like `FocusService`:

```swift
struct CalendarService {
    let auth: GoogleAuth
    let calendarId: String  // "primary" by default

    /// Best-effort. Returns the created event id (for optional patch-on-finish),
    /// or nil on any failure. Never throws to the caller.
    func createBlockEvent(title: String, start: Date, durationMin: Int) async -> String?
}
```

- `POST https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events`
- Body: `summary` = title, `start.dateTime` / `end.dateTime` (RFC3339 + timezone), `transparency = "opaque"`, optional `reminders.useDefault = false` (don't spam the user with calendar alerts for a block already running in the app), optional `description` = "Created by Loft Hours" for traceability.
- Auth header from `await auth.accessToken()`. If nil (not connected / refresh failed), no-op.
- All errors caught, logged to the status mirror, swallowed.

---

## 5. Config additions (`ConfigStore.swift`)

```swift
@Published var calendarSyncEnabled: Bool   // default false
@Published var calendarId: String          // default "primary"
@Published var calendarConnectedEmail: String?  // mirror for the Settings UI ("Connected as you@gmail.com")
```

Same `didSet { defaults.set(...) }` persistence pattern. `calendarConnectedEmail` is a display mirror; the actual auth truth lives in Keychain (`GoogleAuth.isConnected`).

---

## 6. SessionController wiring

The critical detail: **events are per-block, so hook `startFocusBlock(minutes:)`, not `setupEnvironment()`.**

```swift
private func startFocusBlock(minutes: Int) {
    // ... existing block setup ...
    phase = .running
    startTicker()
    persistActive()
    logBlockToCalendar(minutes: minutes)   // <- new, last so it never delays the timer
}

private func logBlockToCalendar(minutes: Int) {
    guard let config, config.calendarSyncEnabled, let s = session else { return }
    let title = s.goal.isEmpty ? "Loft Hours" : "Loft Hours - \(s.goal)"
    let start = Date()
    Task.detached { [calendarService] in
        _ = await calendarService.createBlockEvent(title: title, start: start, durationMin: minutes)
    }
}
```

- `Task.detached` so the network call is fully off the main timer path - the timer starts instantly regardless of network.
- `setupEnvironment()` / `teardownEnvironment()` are **untouched** - calendar has no teardown (events persist by design).
- `discardAndRestart()` (the no-log "start another session") still creates events because it routes back through `startFocusBlock`. Confirm that's desired - it is, since a block ran.

---

## 7. Open decisions / edge cases

1. **Rewind / early skip vs the booked window.** User said "the same amount of time they chose," so v1 books the planned length and ignores overruns/early finishes. *Optional refinement:* capture the returned event id, and on `finishBlock()` PATCH `end.dateTime` to the actual end so the calendar reflects reality. Adds a second API call per block. **Recommend: ship v1 without patching, add later if testers ask.**
2. **Offline at block start.** Event is silently dropped (no retry queue in v1). The status line shows "last sync failed." A retry/backfill queue is a later nicety, not v1.
3. **Which calendar.** v1 defaults to `primary`. Optional calendar picker (list via `GET /users/me/calendarList`) is a nice-to-have; needs a read scope on the calendar list, which slightly widens the OAuth ask. **Recommend: primary-only for v1** to keep the scope minimal.
4. **Timezone.** Always send an explicit IANA timezone (`TimeZone.current.identifier`) with the RFC3339 datetimes so DST/travel doesn't shift the block.
5. **Token revoked server-side** (user removes app in Google security settings). Next call 401s -> we flip `calendarConnectedEmail = nil` and surface "reconnect needed."
6. **Duplicate events on rapid restart.** Low risk (one event per `startFocusBlock`), but if patching is added, guard against double-fire.

---

## 8. App Store / distribution gating (read before building)

- **Google OAuth verification.** Calendar is a **sensitive scope**. An *unverified* OAuth app shows the scary "Google hasn't verified this app" interstitial and is capped at **100 users**. Fine for the current GitHub beta / test users. **Production / public release requires submitting the app for Google OAuth verification** (privacy policy URL, homepage, scope justification, a demo video). Budget days-to-weeks of Google review. This is the real long-pole item, not the code.
- **Network entitlement.** Add `com.apple.security.network.client` to `LoftHours.entitlements`. Already gated in `build-app.sh` to only apply entitlements under a real signing identity (per the HANDOFF Notifier gotcha - a restricted entitlement under ad-hoc signature SIGKILLs the app). The network-client entitlement is *not* restricted, so it's safe under ad-hoc, but keep it in the signed-only block to be consistent and test both.
- **Privacy policy** required by Google for the consent screen. Loft Hours doesn't currently have one - needs a hosted page.
- **App Store privacy label** must declare the calendar data usage if/when MAS submission happens.
- **Custom URL scheme** in `Info.plist` `CFBundleURLTypes` - make sure it's namespaced (`com.lofthours.app`) to avoid scheme collisions.

---

## 9. Build order (suggested)

1. **Google Cloud project** + OAuth desktop client + consent screen (internal/testing mode, add yourself as test user). No code yet.
2. **`GoogleAuth.swift`** - PKCE, `ASWebAuthenticationSession`, token exchange, Keychain, refresh, revoke. Verify with a throwaway "fetch my email" call.
3. **`CalendarService.swift`** - `createBlockEvent`. Manually invoke once to confirm an event lands on the calendar with the right title/busy/duration.
4. **`ConfigStore` additions** + **Settings UI** (Connect button, toggle, status line). Connect/disconnect round-trip.
5. **`SessionController.logBlockToCalendar`** wired into `startFocusBlock`. Run a real 1-minute block, confirm event appears; run a multi-block session, confirm N events.
6. **Entitlements + Info.plist** scheme; test under both ad-hoc and (if available) Developer ID signing.
7. **`SelfTest`** - add a `runCalendarTest()` that exercises title composition + RFC3339/timezone formatting with a stubbed/mock auth (no live network in selftest). Wire into `--selftest`.
8. Update `HANDOFF.md` + `README.md`.

---

## 10. Files touched

**New:** `Services/GoogleAuth.swift`, `Services/CalendarService.swift`
**Edited:** `State/ConfigStore.swift`, `State/SessionController.swift`, `Views/SettingsPanel.swift`, `LoftHours.entitlements`, `Resources/Info.plist`, `SelfTest.swift`, `HANDOFF.md`, `README.md`
