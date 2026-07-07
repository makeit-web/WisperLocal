# WisperLocal — Development Guide

How to build, test, and release WisperLocal. For install and daily use, see the [README](../README.md); user guides are in [`UPUTE-HR.md`](UPUTE-HR.md) / [`GUIDE-EN.md`](GUIDE-EN.md).

## Dev workflow

```bash
bash scripts/setup-whisper.sh    # build whisper.cpp static libs (once)
swift build && swift test        # WisperCore (whisper bridge) + tests
bash scripts/make-app.sh         # assemble + sign WisperLocal.app
open WisperLocal.app
```

CLI for quick transcription checks:

```bash
.build/debug/wisper-cli file <audio.wav> --lang hr|en|auto
```

## Architecture (source map)

- `Package.swift` — SPM targets: `CWhisper` (C module wrapping static whisper.cpp Metal libs), `WisperCore`, `wisper-cli`, `WisperApp`, `WisperCoreTests`.
- `src/WisperCore/`
  - `WhisperContext` — blocking `whisper_full` on a dedicated queue, bridged with a continuation
  - `AudioFile` — 16 kHz resample of input audio
  - `AudioCapture` — AVAudioEngine push-to-talk capture, gated on mic permission
  - `ModelStore` — model discovery; **prefers the Croatian fine-tune** (`ggml-hr-parla-q8_0.bin`) if present, otherwise picks a RAM-appropriate stock model
- `src/WisperApp/`
  - `AppMain` — menu-bar AppDelegate; language default `hr` + Language submenu (hr / en / auto)
  - `HotKey` (Carbon ⌃⌥D), `DoubleTapCtrl` (double-tap Ctrl; needs Accessibility)
  - `TextInjector` — CGEvent Unicode injection; clears modifiers, key-down-only, fail-closed on secure input fields
  - `SplashWindow` — 3 s launch splash; **`isReleasedWhenClosed = false` must stay** (removing it causes a crash)
- `scripts/` — setup, install (source + prebuilt), model download/convert, signing, icon, uninstall, benchmark runner.
- `benchmark/` — Python CER/WER harness (pytest). Results: `docs/research/phase-1-benchmark-2026-07-03.md`.

## Model & language

- Default model: Croatian fine-tune **`GoranS/whisper-large-v3-turbo-hr-parla`**, converted to GGML q8_0 via `scripts/convert-hr-finetune.sh` (~834 MB, keeps English). Benchmarked WER 8.5 % (median 7.1 %) vs 11.7 % stock turbo on FLEURS-hr.
- Language is forced to `hr` by default (auto-detect misfired on mixed HR/EN speakers); the menu-bar Language submenu switches to `en` or `auto`. `translate=false` always.
- Engine: whisper.cpp **v1.9.1**, static Metal build (no Core ML). Swift 6 language mode.
- Models are **never committed** — download scripts only (`scripts/download-model.sh`).

## Code signing (important for releases)

macOS ties the Accessibility/Microphone TCC grants to the app's code-signing identity. Ad-hoc signing produces a new identity every build, which **resets the grants on every update**. Therefore:

- `scripts/make-signing-cert.sh` creates a **stable self-signed identity** in a dedicated keychain (`~/Library/Keychains/wisper-signing.keychain-db`), so signing is non-interactive.
- `scripts/make-app.sh` signs with that identity automatically (falls back to ad-hoc if the keychain isn't set up).
- **Every release must be signed with the same identity**, or users' grants reset. The identity lives only on the release build machine — building releases on a *different* machine creates a new cert, which costs every user a one-time re-grant.
- Self-signed ≠ notarized: Gatekeeper shows "damaged" on other Macs if the app is double-clicked from a browser download. `scripts/install-prebuilt.sh` handles this by removing the quarantine attribute — users must install via the script.

## Release process

1. Bump `CFBundleShortVersionString` in `src/WisperApp/Info.plist`.
2. `bash scripts/make-app.sh` (builds + stable-signs).
3. `ditto -c -k --keepParent WisperLocal.app /tmp/WisperLocal.app.zip`
4. `gh release create vX.Y.Z /tmp/WisperLocal.app.zip --repo makeit-web/WisperLocal --title ... --notes ...`

Note: `install-prebuilt.sh` pins the model asset URL to the release that carries it (currently v0.1.1's `ggml-hr-parla-q8_0.bin`) — a new model means updating that pin.

## Testing

- `swift test` — WisperCore unit/integration tests (Swift Testing).
- `benchmark/` — accuracy harness (`pytest`); run the model matrix with `scripts/run-fleurs-matrix.sh`.
- UI behavior (menu bar, hotkey, permission prompts) is verified with a manual checklist per phase — see `docs/specs/`.

## Docs map

- `docs/specs/` — approved specs incl. the master plan (`2026-07-02-wisperlocal-master-plan.md`) and Swift quality profile
- `docs/decisions/` — decision log (ADRs), one file per decision
- `docs/research/` — benchmarks and API investigations
- `docs/audits/` — review records
