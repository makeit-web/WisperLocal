# WisperLocal — Swift Quality Profile

> **Status:** v0.2 — corrected after the 2026-07-02 adversarial review. Feeds the `no-shortcuts` + `test-coverage` guardians and the review.
> **Author:** Claude (CTO).

## Provenance & licensing
Distilled from community skills (clones in `Studio/Private/_refs/` / `/tmp/swift-skills-eval/`):
- **Adopted:** `AvdLee/Swift-Concurrency` (MIT), `twostraws/Swift-Testing` (MIT), `jazzychad/ios-code-audit` (MIT, review methodology).
- **Cherry-picked:** `twostraws/Swift-Concurrency` (MIT), `twostraws/SwiftUI` (MIT).
- **Idea-only (no license — never copy text):** `twostraws/SwiftAgents`. **Shelved (wrong domain):** `ivan-magda/swift-security`.

Tags: `[AvdLee]` `[tw-conc]` `[tw-test]` `[tw-swiftui]` `[audit]` `[SA]` `[CLAUDE.md]` `[+]`(our own — the macOS/audio/C-interop gap none of the skills cover) `[rev]`(added/corrected by the adversarial review).

---

## (i) Language safety
1. **No `!` force-unwrap / `try!` in `src/`** (allowed in `tests/`). Use `guard let` / `if let`. `[CLAUDE.md][SA]`
2. **No `as!`** — conditional cast + handled failure. `[CLAUDE.md]`
3. **No `!` on actor state after an `await`** — capture into a local first. `[tw-conc][AvdLee]`
4. **No silent `try?` that discards errors.** Ban `try?` around `Task.sleep` in loops (swallows `CancellationError`); check `Task.isCancelled`. `[AvdLee]`
5. **No bare `fatalError()`/`preconditionFailure()` on shipping paths** except provably-unreachable `switch` defaults. Audio/whisper failures degrade to a menu-bar error state, never crash. `[+][CLAUDE.md]`
6. **No `@unchecked Sendable` / `nonisolated(unsafe)` / `@preconcurrency` to silence the compiler.** **Carve-out:** legitimately non-Sendable C types (the whisper.cpp `whisper_context` `OpaquePointer`) get a **permanent, documented `Sendable` wrapper with a stated invariant — no "removal plan" required** (do not let the guardian FAIL these). `[tw-conc][AvdLee][rev]`
7. **Prefer modern API:** no `DispatchQueue.main.async` (use structured concurrency); `FormatStyle` over `DateFormatter`/`NumberFormatter`. `[SA]`

## (ii) Concurrency discipline
8. **Confirm build settings first:** Swift 6 language mode + `SWIFT_STRICT_CONCURRENCY=complete`; verify before reasoning about any diagnostic. `[AvdLee]`
9. **`@MainActor` only for genuinely UI-bound state** (NSStatusItem, settings window). Justify — never blanket. `[tw-conc][AvdLee]`
10. **Audio + whisper off the main actor:** heavy work behind an `actor`/`@concurrent`; hop to `MainActor.run` only for UI mutation. `[AvdLee][CLAUDE.md]`
11. **Structured over unstructured:** `async let`/`withTaskGroup` preferred; `Task.detached` only with a documented reason; **no `Task {}` inside loops.** `[tw-conc][AvdLee]`
12. **Actor reentrancy:** no check-then-act across `await`; capture the async result into a local before writing state. `[tw-conc]`
13. **whisper.cpp bridge — `whisper_full` is a SYNCHRONOUS, multi-second BLOCKING C call (not a callback).** Dispatch it to a **dedicated `Thread`/serial queue** and bridge via `withCheckedContinuation` (resumed **exactly once on every path**). **Never `await` it directly on the cooperative pool** (starvation). `[tw-conc][+][rev]`
14. **Bounded stream buffers:** the mic→transcription `AsyncStream` uses `.bufferingNewest(n)` — never `.unbounded` (8 GB). `[tw-conc][+]`
15. **CoreAudio capture:** `AVAudioEngine.installTap` runs on a **background audio queue (not the `AURenderCallback` real-time thread)** — so the rule here is **no *unbounded* blocking / no *unbounded* allocation** inside the tap, hand heavy work to an actor *outside* it. The **strict lock-free / zero-alloc law is reserved for a TRUE render callback** (`AVAudioSinkNode` / `AURenderCallback`) if one is ever used. Capture must **explicitly resample 48 kHz→16 kHz mono via `AVAudioConverter`** (don't assume the tap yields 16 k). `[+][rev]`

## (iii) Error handling
16. **Every `throws` handled explicitly**; `Task {}` closures catch and surface — no swallowing. `[tw-conc][CLAUDE.md]`
17. **Distinguish `CancellationError`** (normal) from real errors; don't alert/retry on cancellation. `[tw-conc]`
18. **Failures surface to the user:** menu-bar icon state + optional notification + local log. `[CLAUDE.md]`

## (iv) Testing
19. **Swift Testing for unit + integration** (XCTest only for latency `measure` + any XCUITest). `[tw-test][AvdLee]`
20. **FIRST + happy / boundary / invalid-input (+ concurrency) tests** per function. `[tw-test]`
21. **`struct` suites, `init` over `setUp`, `#expect`, `#require`** for preconditions & optional unwrap (no force-unwrap in tests). Never `#expect(!x)` — use `#expect(x == false)`. `[tw-test]`
22. **Inject hidden dependencies** behind protocols: whisper engine, audio source, `Clock`, `FileManager`. `[tw-test]`
23. **Leak tests** for long-lived objects (audio loop, hotkey listener): `weak` ref → assert nil after release. `[AvdLee]`
24. **Parameterized tests** across HR/EN audio fixtures. `[tw-test]`
   *(Note: TDD ordering is a review-checklist judgment, not a read-only-guardian gate — squashed main history hides it.)* `[rev]`

## (v) Performance / memory (8 GB + real-time audio)
25. **Measure before optimizing** — Instruments; no perf claim without a trace. `[AvdLee]`
26. **Start synchronous; add async/parallel only when profiled.** `[AvdLee]`
27. **No retain cycles in stored tasks:** `[weak self]` + explicit `cancel()` in `isolated deinit`. `[AvdLee]`
28. **Model memory budget:** large-v3 (~3 GB) is tight on M1 8 GB — prefer `mmap`, gate model on chip **and *available* RAM/pressure** (dynamic drop to q5_0), verify residency (`vm_stat`). `[+][rev]`
29. **Test on both real machines** (M1 8 GB, M4 16 GB) — "simulators lie." `[AvdLee][+]`

## (vi) Security / privacy
30. **No network egress except the model-download module** — and enforced by a **build-phase binary scan (`otool -L`/`nm`), not just a source grep** (the app is non-sandboxed, so entitlements can't block egress). Detection covers `URLSession`, `Network`/`NWConnection`, raw `socket()`/`getaddrinfo`, `Process`/`NSTask`, `NSWorkspace.open(URL)`, `WKWebView`, and whisper.cpp C-level networking. `[CLAUDE.md][rev]`
31. **No secrets in repo / UserDefaults / plist.** `[CLAUDE.md]`
32. **Model integrity:** verify SHA256 **against a committed constant** + **pinned HF repo revision**; HTTPS-only, no ATS exception, no `curl -k`. `[+][rev]`
33. **TCC permissions:** only **Microphone** uses an `Info.plist` usage string; **Accessibility & Input-Monitoring are granted at runtime** (`AXIsProcessTrusted()` / `IOHIDCheckAccess`), not via plist — request correctly, never work around, handle denial gracefully. `[+][rev]`
34. **Text-injection safety:** check **`IsSecureEventInputEnabled()` before any `CGEventPost`/AX write**, **fail-closed on unknown field subrole** (Chrome/Electron password fields lack `AXSecureTextField`), **re-check focus immediately pre-post (TOCTOU)**; validate Croatian diacritics survive injection. `[+][rev]`
35. **No `NSPasteboard` for injection** — it can sync the transcript via Universal Clipboard to iCloud/other devices (invisible egress). Prefer AX/`CGEvent`; if paste is unavoidable, mark host-local + restore prior contents. `[+][rev]`
36. **No `.public` OSLog interpolation on dynamic/transcript strings** (default `.private`/`.sensitive`); the file-logger API must be **type-level unable to accept** transcript/audio values. Benchmark logs use **hashed IDs, never absolute sample paths.** `[+][rev]`
37. **Pin dependencies:** `Package.resolved` at exact revisions + whisper.cpp pinned commit; a new dependency is a review gate. **No embedded auto-updater** (network + auto-RCE surface). `[+][rev]`

## (vii) Reviewer / audit discipline `[audit]`
38. **Read-only audit, `file:line` citations** — "throughout the codebase" is never acceptable for Critical/High.
39. **Conservative severity:** Critical = crash / data loss / **privacy leak** / memory corruption only. **Verify every Critical by opening the cited line** before propagating.
40. **Group findings by root cause**, numbered, with an explicit "What was NOT audited" section. Maps onto the risk-scaled review.

---

## Coverage note (the macOS/audio gap we own)
Menu-bar lifecycle (`NSStatusItem`, `LSUIElement`, `SMAppService`); global hotkey (`RegisterEventHotKey` preferred over keylogger-grade event taps; conflict detection); AVAudioEngine capture + resampling + route-change; C/C++ interop with whisper.cpp (`OpaquePointer` lifetime, no-copy audio hand-off, threading); AX text injection (main-thread, secure-field, diacritics, frontmost-app capture); TCC flows; model provisioning + checksum + memory; stable-self-signed / hardened-runtime / notarization. **This is where WisperLocal's real risk lives.**
