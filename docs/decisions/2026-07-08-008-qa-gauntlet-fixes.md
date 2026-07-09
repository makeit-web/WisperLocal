# 008 — v0.1.8: QA-gauntlet fixes (external report 2026-07-08)

- **Date:** 2026-07-08
- **Status:** approved (CEO approved batches 1–3; explicitly excluded any change
  to lost-dictation behavior)
- **Input:** `WisperLocal QA Report 2026-07-08.md` (Curtis) — 57 confirmed
  findings (2 HIGH, 18 MEDIUM, 33 LOW, 4 INFO), each adversarially verified by
  an external model. Key findings were independently re-verified against the
  code before any fix.

## What was decided and why

### 1. Dictation state machine (HIGH: hot mic under an idle icon)
`AppDelegate.isRecording: Bool` + icon-as-state allowed a real race: toggling
during an in-flight transcription started a second recording, and the first
completion unconditionally reset the icon to 🎤 while the mic was hot.
**Decision:** one `DictationState` enum (`loading / idle / recording /
transcribing / notice(glyph)`); the icon is derived from state in a single
`didSet`; `toggle()` ignores input while `.transcribing` (no concurrent
pipelines, which also removes the rapid stop/start race that showed a
misleading 🚫). The state machine stays in the app delegate (thin UI glue,
manual checklist) — all logic underneath it was extracted and unit-tested
instead (see 2–4). Model load moved off the main actor (`Task.detached`);
`.loading` state gates dictation until ready.

### 2. TextInjector extracted to WisperCore (HIGH: untestable privacy invariant)
Secure-field refusal and surrogate-safe chunking lived in the untestable
executable target. **Decision:** moved to WisperCore behind injectable probes
(`InjectionProbes`, same pattern as `ModelStore.resolveModelPath`), pure
`chunkRanges` split out; 14 tests pin the decision order, zero-event refusals,
chunk math, and the TOCTOU abort. **TOCTOU fix:** `IsSecureEventInputEnabled()`
is re-checked before *every* chunk (fail closed mid-injection). The AX subrole
probe deliberately stays pre-loop only: two synchronous IPC round-trips per
chunk could stall behind a hung frontmost app, and async auth dialogs flip the
global secure-input flag that IS re-checked. Injection runs on a dedicated
serial queue (§13 — `usleep` pacing must not block the cooperative pool).
Accepted fail-open of the AX probe on failed queries is unchanged (ADR 007)
but now documented as covering ALL query failures, with
`IsSecureEventInputEnabled` as the authoritative guard.

### 3. Control characters filtered at injection (LOW, defense-in-depth)
Whisper output is untrusted model output; a `\n` typed into a terminal is
Return. **Decision:** in `TextCleanup.forInjection`, control-scalar runs that
break lines (incl. tab, U+2028/29) become one space; other C0/C1 controls are
dropped. Injection-time only — the faithful transcript is untouched (ADR 006).

### 4. Double-tap Ctrl: pure detector + Caps Lock fix (MEDIUM)
`flags == .control` never matched while Caps Lock was latched — the primary
trigger silently died. **Decision:** `DoubleTapDetector` (WisperCore, 11 tests)
with `chordInputs` masking to chording modifiers only. New pinned behavior: a
modifier joining while Ctrl is held invalidates the pending tap, so ⌃⌥D + a
reflexive Ctrl tap no longer double-toggles.

### 5. AudioCapture: buffer release + truncation surfacing (MEDIUM)
**Decision:** `stop()` now returns `Recording { samples, truncated }`; the
native buffer is released at stop (was: up to ~115 MB resident while idle,
raw audio of the last dictation lingering in memory). Hitting the 10-min cap
logs once and surfaces a notification (was: silent truncation = hidden wrong
result). Tested through the engine-free `accumulate`/`finishRecording` seam.

### 6. Model fallback chain matches what installers provision (MEDIUM)
`install-prebuilt.sh` ships only the fine-tune and deletes the turbo, so the
turbo last-resort was a rung no colleague's Mac could satisfy. **Decision
(option b, CEO-approved):** keep the disk-saving deletion; chain is now
fine-tune → RAM model → turbo (dev machines) → *fine-tune as the last-resort
name*, so the failure path names the file the installer can restore.
Cross-reference comments added at every site that re-encodes model names
(ModelStore, download-model.sh, make-app.sh, install-prebuilt.sh); a shared
`models.env` was deliberately deferred until the catalog actually churns.

### 7. Signing & egress hardening (MEDIUM)
`--options runtime` (hardened runtime) on every codesign path + a hard
post-sign verification — without it, any same-user process could
DYLD-inject and inherit the mic/AX TCC grants. **Critical catch from the
Quality Review pass:** hardened runtime *denies the microphone outright*
without `com.apple.security.device.audio-input` — the QA report's fix
suggestion omitted this, and the first rebuild shipped an empty entitlements
blob. Added `src/WisperApp/WisperLocal.entitlements` (audio-input only,
unrestricted — works with self-signed/ad-hoc), `--entitlements` on all three
codesign paths, and a post-sign hard-verify that the entitlement is embedded.
Egress deny-list extended with
`NSURLConnection | CFSocket | CFStreamCreatePairWithSocket | getStreamsToHost`;
raw BSD syscall names deliberately NOT matched (false-positive on libSystem —
the QA verifier itself flagged this). Keychain passwords now go to `security`
via stdin (`security -i`), never argv; the password must stay hex (documented
at the generation site — security's tokenizer re-parses the stdin batch).

### 8. Installer robustness (MEDIUM/LOW)
install-prebuilt.sh: stage-then-swap (never delete the old app before the new
one is verified + extracted), pre-existing model re-verified against its
SHA256 (a partial download can no longer become permanent), `curl --retry`
(+ resume for the 834 MB model). install.sh: quits the running instance before
replacing the bundle. uninstall.sh: also removes `~/Library/Logs/WisperLocal`.

### 9. Supply-chain pins (MEDIUM/LOW)
- whisper.cpp: commit pin `f049fff9…` asserted on every setup run (tags are
  mutable; the tag→commit mapping was verified against upstream `ls-remote`).
- Model downloads (from-source path): SHA256 pins, cross-checked between the
  local benchmarked files and Hugging Face's published LFS oids; pre-existing
  files re-verified, corrupt files removed and re-fetched.
- convert-hr-finetune.sh: HF revision + openai/whisper commit pinned,
  safetensors-only download (**no pickle ever reaches the signing machine**;
  the repo has no pytorch .bin, so `from_pretrained` uses safetensors),
  `mktemp -d` instead of reusable fixed /tmp paths. pip versions stay unpinned
  — accepted trade-off for a one-time dev script whose output ships checksummed.
- prepare_fleurs.py: the silent `trust_remote_code=True` fallback (unpinned
  remote code execution) is removed outright; failure now instructs upgrading
  `datasets` instead of escalating.

### 10. Benchmark/test/CLI hygiene (LOW)
- `#require` → `.enabled(if:)` so a bare checkout skips instead of failing;
  dev workflow in DEVELOPMENT.md now lists the model download step.
- run_bench.py: `rc` column, failures counted and EXCLUDED from means,
  `exit 1` on any failure, per-clip timeout; RTF-includes-model-load caveat
  documented. run-fleurs-matrix.sh: `set -e` + portable `cd` (was hardcoded to
  a personal home directory).
- score.py empty-reference branch pinned by tests.
- wisper-cli: `--seconds` validated (was a trapping crash), unknown flags are
  usage errors (were silently ignored), model loads during recording.

## Explicitly NOT done (CEO decision, 2026-07-08)
The QA report proposed restoring a "Copy last transcript" recovery path for
blocked injections. That conflicts with the v0.1.7 decision (ADR 007 line:
padlock stays, most private). **Blocked dictations remain undelivered and
unrecoverable by design**; the stale comments that promised a menu recovery
path were corrected to match this reality. No transcript retention was added.

## Also deferred
- CI workflow (INFO finding): worthwhile, but a separate cost/benefit call.
- Benchmark single-load-per-model rework: the harness already served ADR-003;
  the RTF bias is now documented instead of re-architected.
- `scripts/models.env` single source of truth: deferred until model churn
  justifies it (cross-reference comments in place).

## Review passes (ADR 004: injection touched → full review)
1. **Claude Quality Reviewer** (independent agent over the full diff): found
   the missing audio-input entitlement (critical — fixed, see §7), the CLI
   `--seconds` bound exceeding the 600 s capture cap (fixed: bound = 600), a
   hotkey-conflict notification promising the double-tap works without
   Accessibility (fixed: wording now conditioned on trust), the QA report file
   not being gitignored like its audit predecessor (fixed), and the hex-only
   constraint on the keychain password being implicit (documented). All other
   areas — state machine paths, sendability, detector edges, chunker,
   scripts, benchmark — reviewed clean.
2. **Codex adversarial pass** (after the CEO repaired the broken CLI install):
   declared the chunker, double-tap detector, MainActor/detached-task paths and
   benchmark accounting CLEAN under adversarial re-attack. Two real findings,
   both fixed: (a) install-prebuilt.sh still deleted the old app before the
   final `mv` despite the stage-then-swap comment — now swaps through a
   restorable backup and puts the previous version back if the swap fails;
   (b) the whisper.cpp commit pin accepted a dirty checkout at the right
   commit — setup-whisper.sh now also requires a clean tree. Its third finding
   (installer still pins v0.1.7) is the deliberate pin-to-published-release
   behavior; the pins move atomically when the v0.1.8 asset is published.

## Verification
`swift test`: 62 tests green (was 25). `pytest`: 21 green (was 15). App
rebuilt with hardened runtime (`flags=0x10000(runtime)`) AND the audio-input
entitlement verified in the signature; egress scan clean; stable-signed.
wisper-cli argument errors and JFK-sample E2E verified by running the binary.
`security -i` stdin behavior verified against a throwaway keychain before
adoption. **Outstanding manual gate before releasing v0.1.8:** one real
dictation on the rebuilt hardened-runtime bundle (mic → transcribe → inject),
since hardened runtime + entitlement changes the mic authorization path.
