# WisperLocal — Session Handoff

> **Updated:** 2026-07-06 · **Author:** Claude (CTO)
> Read this first to resume. Then: `docs/specs/2026-07-02-wisperlocal-master-plan.md` (the approved plan) and the memory dir.

## TL;DR — where we are
A **working** local macOS dictation app exists (Phases 1–4 done) and is on GitHub. Menu-bar app: **double-tap Ctrl** (or ⌃⌥D) → record → transcribe locally (Croatian default) → **type into the focused app**. Confirmed on the user's real voice: **Croatian is excellent**, AirPods fine, setup clean.

**⛔ IMMEDIATE OPEN ISSUE — injection quality.** The user reports the directly-typed text comes out **worse than the clipboard-paste did**. Transcription path is unchanged (same model/language/capture), so the suspect is the **CGEvent text injection garbling the text**. A fix was pushed (clear modifiers + set Unicode on key-down only). **Awaiting the user's A/B answer:** are *letters* garbled (→ injection bug) or *words* wrong (→ transcription/mic)? **Plan B is ready:** switch `TextInjector` to the **clipboard-paste method** (put text on pasteboard → synthesize ⌘V → restore prior clipboard) — the reliable approach SuperWhisper/MacWhisper use; small privacy trade-off (§35) to confirm with the user.

## Environment
- **Machine:** Mac mini M4, 16 GB, macOS 26.5.1 (this is the "accuracy tier"; the MacBook Air M1 8 GB tier is untested — needs a session on that machine).
- **Repo:** `/Users/akujundzic/Studio/Private/WisperLocal`. Git remote **`makeit-web/WisperLocal`** (GitHub, PRIVATE, ssh). Branch `main`, everything pushed (latest `bd4fc13`).
- **Reference clones** (governance/Swift source): `Studio/Private/_refs/{dev-project-template, ai-engineering, swift-agent-skills}`.

## Build & run
```
bash scripts/setup-whisper.sh     # once: clone+build whisper.cpp v1.9.1 static (Metal) + stage headers
bash scripts/make-app.sh          # build WisperApp -> WisperLocal.app (ad-hoc signed) + provision models
open WisperLocal.app              # grant Microphone + Accessibility, then double-tap Ctrl to dictate
swift build && swift test         # WisperCore tests (whisper bridge transcribes EN+HR)
.build/debug/wisper-cli file whisper.cpp/samples/jfk.wav --lang auto   # CLI transcribe
benchmark/.venv/bin/python -m pytest benchmark/tests/                  # 15 harness tests
```
Models are gitignored (`models/`); `make-app.sh` copies the RAM-selected model to `~/Library/Application Support/WisperLocal/models/`. On the M4 the app loads `large-v3 q8_0`.

## What was built (the arc, this session)
1. **Governance/plan** — deep Whisper research (adversarially verified) → master plan → **5-reviewer adversarial hardening** → independent verification (9/9) → committed. Swift Quality Profile, 7 guardians, ADRs 001–005, audit record. All in `docs/`.
2. **Phase 1 benchmark** — whisper.cpp v1.9.1 built; Python CER/WER harness (`benchmark/`); **FLEURS-hr 914 samples**: `large-v3 q8_0` WER **11.0%** (median 9.1%), turbo q8_0 12.4%; per-tier confirmed; RAM measured (turbo 1.1 GB / large-v3 q8_0 2.6 GB / f16 4.0 GB). See `docs/research/phase-1-benchmark-2026-07-03.md`.
3. **Phase 2** — Swift ↔ whisper.cpp bridge (SPM). Transcribes EN+HR, tests pass.
4. **Phase 3** — menu-bar app, hotkey, mic-permission flow, model selection.
5. **Phase 4** — text injection (Accessibility/CGEvent), language menu, double-tap Ctrl.

## Architecture (source map)
- **`Package.swift`** — SPM targets: `CWhisper` (C module, links **static** whisper.cpp Metal libs; headers staged by setup-whisper.sh, gitignored), `WisperCore` (library), `wisper-cli` (exe), `WisperApp` (menu-bar exe), `WisperCoreTests`. Static-lib link flags live here (`whisperLink`).
- **`src/WisperCore/`**
  - `WhisperContext.swift` — `final class @unchecked Sendable`; blocking `whisper_full` on a dedicated `DispatchQueue` + `CheckedContinuation` (Swift profile §6/§13).
  - `AudioFile.swift` — load/resample audio to 16 kHz mono; `resampleMono`.
  - `AudioCapture.swift` — `AVAudioEngine` push-to-talk; mic-permission-gated via `AVCaptureDevice` (avoids the uncatchable ObjC crash).
  - `ModelStore.swift` — RAM-based model path (Application Support, else `models/`).
- **`src/WisperApp/`**
  - `AppMain.swift` — `@main @MainActor AppDelegate`; NSStatusItem, menu (Language submenu, Open Accessibility Settings, Quit), record→transcribe→deliver, `language = "hr"` default.
  - `HotKey.swift` — Carbon global hotkey ⌃⌥D (no Accessibility needed).
  - `DoubleTapCtrl.swift` — global flags monitor, double-tap Control (NEEDS Accessibility).
  - `TextInjector.swift` — CGEvent Unicode injection; `AXIsProcessTrusted`, fail-closed on secure fields; **← the file to change for Plan B (paste method)**.
  - `Info.plist` — LSUIElement, NSMicrophoneUsageDescription, bundle id `hr.makeit.wisperlocal`.
- **`scripts/`** — `setup-whisper.sh`, `make-app.sh`, `make-signing-cert.sh`, `run-fleurs-matrix.sh`.
- **`benchmark/`** — `normalize.py` (Croatian normalization, digits-as-is v1), `score.py` (CER/WER via jiwer), `run_bench.py`, `prepare_fleurs.py`, `tests/`. venv at `benchmark/.venv` (gitignored). `num2words` has NO Croatian (number-normalization refinement blocked).

## Key decisions
- **Engine:** whisper.cpp v1.9.1 (`f049fff`), **static Metal, no Core ML** (Core ML is encoder-speed-only ~1.25×, fragile Python toolchain — deferred).
- **Models per-tier (ADR-003):** Air → `large-v3-turbo q8_0` (1.1 GB); Mac mini M4 → `large-v3 q8_0` (2.6 GB). q8_0 baseline.
- **Language (revised 2026-07-06):** default **forced `hr`** (user found `auto` misdetects/mistranslates his English) + a **Language menu** (hr/en/auto) to switch manually. `translate=false` always. (`wisper-cli` default is still `auto` — minor inconsistency, fine for the dev tool.)
- **Testing:** Swift Testing + XCTest for latency (ADR-002). **Governance:** lean guardians, main-only, risk-scaled review (ADR-004).
- **Signing:** ad-hoc for now. **Stable self-signed (ADR-005)** needs the user to run `make-signing-cert.sh` **and click "Always Allow"** on the keychain prompt (can't be done autonomously). Until then, each rebuild may require re-granting Accessibility.

## Open issues / next steps (priority)
1. **Injection quality (BLOCKING good UX).** Get the user's A/B (letters vs words). If letters → implement **paste method** in `TextInjector.swift`: save `NSPasteboard.general` contents → set transcript → post ⌘V (CGEvent, keycode 9 with .maskCommand) → restore previous contents after a short delay. Confirm the §35 trade-off with the user.
2. **Stable signing** — have the user run `make-signing-cert.sh` + "Always Allow" so Accessibility grants persist across rebuilds.
3. **Double-tap Ctrl** — possible false trigger on rapid double Ctrl+C; refine timing/guard if the user hits it.
4. **Phase 5 polish** — settings (hotkey rebind, model override, persist language choice), visual/audio feedback (SF Symbols icon states instead of emoji), launch-at-login (`SMAppService`), auto-punctuation validation.
5. **Deferred Phase 1** — subjective gate (largely validated by real use now), Common Voice HR (spontaneous speech), **HR fine-tune** `GoranS/whisper-large-v3-turbo-hr-parla` (needs a torch GGML conversion — the user wants this "at the end"), Core ML latency, **Air 8 GB tier** run (separate session on that machine).
6. **Recording UX** — currently toggle (tap to start, tap to stop). Consider hold-to-talk and Silero VAD silence-trim (per Phase 2 spec).

## Task state (harness)
Tasks #1–16 complete (plan→benchmark). #17 (Phase 1 build) left in_progress = benchmark done, subjective/fine-tune deferred. #18/#19/#20 (Phases 2/3/4) complete. No open harness task for the injection issue — create one on resume.

## How to resume
1. Read this + the master plan + memory (`project_state`, `app_validated_auto_language`).
2. Ask the user for the injection A/B result if not already given; most likely implement the paste method.
3. The app is functional — remaining work is injection reliability + Phase 5 polish + the deferred Phase-1 finalization (HR fine-tune with the user).
