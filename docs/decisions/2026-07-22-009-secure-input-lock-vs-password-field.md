# 009. Distinguish a session-wide secure-input lock from a password field

**Date:** 2026-07-22
**Status:** Accepted (v0.1.8)
**Deciders:** Claude (CTO, recommends) + User (CEO, approves)

## Context
Real incident, 2026-07-22. The user tried to dictate into Slack on a second Mac
and got the 🔒 notice — *"Password field — Not typing into a secure field, for
your safety."* Nothing could be typed **anywhere**, not just in Slack.

Root cause: **Microsoft Word held the session-wide secure event input lock.**
While that lock is held, macOS blocks synthesized keyboard events system-wide, so
`IsSecureEventInputEnabled()` returned true and `TextInjector` refused every
injection. Word takes the lock for its own password/sign-in prompt and is known
to keep holding it. Quitting Word released it and dictation worked again.

Two defects made a 30-second fix take a diagnostic session:

1. **The message was wrong.** `TextInjector` collapsed two unrelated conditions
   into one result, `.secureField`. There was no password field anywhere — the
   real condition was a global lock — but the user was told there was, and given
   no action to take.
2. **Nothing was logged.** A refused injection wrote no line to
   `~/Library/Logs/WisperLocal/`, so the log was silent for the whole incident
   and the culprit had to be found by hand with
   `ioreg -l | grep SecureInput`.

## Investigation (measured, not assumed)
`IsSecureEventInputEnabled()` says *whether* input is locked, never *by whom*.
The window server publishes a pid in the IORegistry root's `IOConsoleUsers`
array under `kCGSSessionSecureInputPID`. Probing it on 2026-07-22 produced a
result that changed the design:

| Probe | Lock taken by | Registry reported |
|---|---|---|
| plain CLI process | itself (pid 34497) | Universal Control (`.accessory`) |
| process promoted to `.regular` app | itself (pid 55862) | **Code / VS Code — the frontmost app** |

Baseline was `nil` before each run and `nil` after release, so the reads were
sound. **The reported pid is the application that was frontmost when the lock was
engaged, not the process that requested it.** For the ordinary case — a GUI app
opening its own password prompt while it is frontmost — the two coincide, which
is exactly why the Word attribution was correct and actionable. For a background
process taking the lock, they do not.

A second measurement: `IsSecureEventInputEnabled()` reports `false` inside the
test process even while the registry shows the lock, and `true` in a process
with an `NSApplication` and a run loop. The shipped menu-bar app is the latter,
so the app is unaffected; the test suite must not assert on it.

## Options considered
1. **Name the blocking app as fact** — *"Keyboard locked by Microsoft Word. Quit
   it."* Most actionable, but the measurement above shows attribution can point
   at an innocent frontmost app. Telling a user to quit the app they are typing
   into is worse than the vague message it replaces. **Rejected.**
2. **Say nothing about which app** — *"Another app has locked keyboard input."*
   Safe but leaves the user hunting, which is the exact pain being fixed.
   **Rejected as insufficient.**
3. **Report only what the OS actually reports** (chosen). The title states what
   is certain — input is locked system-wide. The body states the literal
   observation rather than a verdict: *"Locked while Microsoft Word was in
   front — close its password prompt, then dictate again."* That sentence stays
   true even when the frontmost app was not the requester, and the suggested
   action is non-destructive, so no user is ever told to quit an app that may
   be innocent — including the one they are dictating into.

   An earlier draft read *"Likely Microsoft Word — … or quit it"*. The
   adversarial review (2026-07-22) rejected it: "Likely" hedges the attribution
   but the instruction still points at a possibly-innocent app. Adopted.

## Decision
- Adopt **option 3**.
- Split the result: `InjectionResult.secureInputLocked(likelyApp: RunningApp?)`
  for the global lock, `.secureField` kept for a genuine password field. The
  associated value is named `likelyApp` so no call site can present it as fact
  by accident.
- `RunningApp` is constructible from a live pid only, and **refuses any process
  that is not `.regular`** — only an app with a dock icon can actually be found
  and quit, and a background name would misdirect.
- The holder lookup (two IPC round trips) runs **only on the refusal path**,
  never per chunk — enforced by a test.
- Log every refusal — lock, password field, and missing Accessibility. The new
  `Log.event(_:app:)` overload takes `RunningApp`, not `String`, so this change
  adds **no** new way for runtime text to reach the log: in a release build a
  `RunningApp` can only come from a live pid.

  Precisely stated, `Log` accepts compile-time `StaticString` text, integer
  status codes, `Error` values, and now `RunningApp`. The `Error` path is the
  one place runtime text can still reach the file — it predates this change and
  is left untouched here (surgical scope), but the guarantee should be described
  as "a transcript cannot be logged by mistake", not as absolute. Tightening the
  `Error` overload is logged as follow-up work, not done in this ADR.

## Consequences
- The user gets a system-wide-lock message that names a likely culprit and an
  action, instead of a false "password field" claim.
- Refusals are now visible in `~/Library/Logs/WisperLocal/wisperlocal.log`.
- **Residual risk (accepted):** when a background process takes the lock, the
  named app is whichever was frontmost at the time and may be innocent. The
  hedged wording ("Likely …") is the mitigation; the log records what was seen.
- The 🔒 glyph is still sticky by design (CEO, v0.1.7) — it reflects the last
  attempt, not live state, and clears on the next successful dictation. This
  misled the user during the incident but the behaviour is unchanged here.
- `SecureInputTests` must stay `.serialized`: two of its tests take the real
  process-wide lock and racing them makes one release it under the other.

## Review (CLAUDE.md three-pass, Phase 4 injection code)
Claude Quality Reviewer + Codex standard + Codex adversarial, all 2026-07-22.
Both Codex passes ran in a sandbox that denied them `swift build` / `swift test`,
so their findings are from reading the code; the build/test evidence below is
from this machine. Findings and dispositions:

- **Fixed** — `RunningApp`'s arbitrary-`String` initializer was `internal`, so
  code inside `WisperCore` (where transcripts live) could have wrapped a
  transcript and logged it. Now `#if DEBUG`, i.e. absent from shipped builds.
- **Fixed** — user-facing wording still instructed the user to quit a possibly
  innocent app (see option 3 above).
- **Fixed** — the two tests that take the real lock now release it through a
  `defer` guarded so `DisableSecureEventInput()` runs exactly once (the lock is
  reference-counted per process).
- **Corrected claim, code untouched** — `Log` also accepts `Error` values, whose
  runtime description reaches the file, so the privacy guarantee is "a
  transcript cannot be logged *by mistake*", not absolute. Wording above fixed;
  tightening the `Error` overload is follow-up work.
- **Rejected as out of scope, escalated to the CEO** — the adversarial pass
  flagged that `focusedFieldIsSecure()` is not re-checked per chunk, so a focus
  change to a native secure field that does *not* flip global secure input could
  receive later chunks. Real, but **pre-existing and deliberate**: ADR 008 checks
  it only up front because it is two synchronous IPC round trips that stall if
  the frontmost app hangs, and the residual risk is already recorded in ADR 007.
  This change does not alter that behaviour. Reversing it is a separate decision.

## Verification
- 69 tests pass (`swift test`), three consecutive runs, no flakes.
- Live integration test takes the real lock and asserts the registry read sees
  it and that it is released again.
- `RunningApp(pid:)` is asserted against every running application: no
  non-`.regular` process is ever nameable.
- Real-world confirmation: after quitting Word the lock cleared and dictation
  into Slack worked.
