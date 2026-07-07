# WisperLocal — Session Handoff

> **Updated:** 2026-07-07 · **Author:** Claude (CTO)
> Read this first to resume. Then: `README.md`, `docs/specs/2026-07-02-wisperlocal-master-plan.md`, and the memory dir.

## TL;DR — where we are
A **working, shipping** local macOS dictation app. Menu-bar app: **double-tap Ctrl** (or ⌃⌥D) → speak → text is typed into the focused app, 100% offline. **Croatian is the default and is excellent** (a Croatian fine-tune model, WER ~8.5%). Distributed as **prebuilt GitHub Releases** (latest **v0.1.4**) installable with one terminal command. The app is **stably self-signed**, so macOS keeps the Microphone/Accessibility grant across updates. Confirmed working on the user's real voice (Croatian + AirPods).

## Environment / repo
- **Machine (build):** Mac mini M4, 16 GB, macOS 26.5.1. The user also runs it on a **MacBook Air M1 8 GB**.
- **Repo:** `/Users/akujundzic/Studio/Private/WisperLocal`. GitHub **`makeit-web/WisperLocal`** — **currently PUBLIC** (the user chose this so the prebuilt install works without auth; set back to private later with `gh repo edit makeit-web/WisperLocal --visibility private --accept-visibility-change-consequences`). Branch `main`, everything pushed.
- Reference clones (governance/Swift source): `Studio/Private/_refs/`.

## Install / build / run
- **Prebuilt (no build tools):** `curl -fL https://raw.githubusercontent.com/makeit-web/WisperLocal/main/scripts/install-prebuilt.sh -o /tmp/wl-install.sh && bash /tmp/wl-install.sh` → downloads the app + Croatian model, removes quarantine.
- **From source:** `bash scripts/install.sh` (needs Command Line Tools — NOT full Xcode — + Homebrew).
- **Dev:** `bash scripts/setup-whisper.sh` (once) → `swift build && swift test` (WisperCore) → `bash scripts/make-app.sh` → `open WisperLocal.app`. CLI: `.build/debug/wisper-cli file <wav> --lang hr|en|auto`.
- **Uninstall:** `bash scripts/uninstall.sh`.
- **First run (once per machine):** grant Microphone, then Accessibility (menu 🎤 → Open Accessibility Settings → enable → quit & relaunch). With stable signing this grant now persists across updates.

## Releases (GitHub)
- **v0.1.0** first prebuilt (turbo model). **v0.1.1** Croatian fine-tune model (asset `ggml-hr-parla-q8_0.bin`, 834 MB — the model lives here; `install-prebuilt.sh` pins the model URL to v0.1.1). **v0.1.2** splash + icon + author credit. **v0.1.3** crash fix (splash `isReleasedWhenClosed`) + cleaner splash + uninstall.sh. **v0.1.4** stable self-signed release signing (grants persist).
- **Release process:** `bash scripts/make-app.sh` (stable-signs) → `ditto -c -k --keepParent WisperLocal.app /tmp/WisperLocal.app.zip` → `gh release create vX.Y.Z /tmp/WisperLocal.app.zip --repo makeit-web/WisperLocal ...`. Bump `CFBundleShortVersionString` in `src/WisperApp/Info.plist` first.

## ⭐ Stable signing (IMPORTANT for future releases)
Ad-hoc signing made macOS reset the Accessibility grant on every update. Fixed with a **stable self-signed identity** kept in a **dedicated keychain** so signing is non-interactive:
- `scripts/make-signing-cert.sh` created keychain `~/Library/Keychains/wisper-signing.keychain-db` (password `wisper-signing`) holding the `WisperLocal` code-signing identity (hash `66466AC10D83AB90C2E5AA4A904DA2385F992019` on this machine).
- `make-app.sh` signs by that hash (unambiguous; a duplicate `WisperLocal` in the login keychain was deleted). Result: `Authority=WisperLocal`, verifies clean.
- **Keep signing every release with this same identity** or the grant resets. This keychain lives on the M4 build machine — if you ever build on another machine, re-run `make-signing-cert.sh` there (a *new* cert = a one-time re-grant for users). Self-signed is untrusted by Gatekeeper, so the "damaged/padlock" on other Macs is handled by `install-prebuilt.sh` removing the quarantine (users must install via the script, not double-click).

## What was built this project (arc)
Governance/plan (5-reviewer hardened, verified) → Phase 1 whisper.cpp + benchmark (FLEURS-hr 914: large-v3 q8_0 WER 11%, turbo 12.4%) → Phase 2 Swift bridge → Phase 3 menu-bar app → Phase 4 text injection → then productization (installers, releases, icon, splash, stable signing) + the **Croatian fine-tune** shipped as default.

## Architecture (source map)
- `Package.swift` — SPM: `CWhisper` (C module, static whisper.cpp Metal libs), `WisperCore`, `wisper-cli`, `WisperApp`, `WisperCoreTests`.
- `src/WisperCore/` — `WhisperContext` (blocking whisper_full on a dedicated queue + continuation), `AudioFile` (16 kHz resample), `AudioCapture` (AVAudioEngine push-to-talk, mic-permission-gated), `ModelStore` (**prefers `ggml-hr-parla-q8_0.bin`** if present, else RAM-based).
- `src/WisperApp/` — `AppMain` (menu-bar AppDelegate; **language default `hr`** + Language submenu hr/en/auto; credit item), `HotKey` (Carbon ⌃⌥D), `DoubleTapCtrl` (double Ctrl, needs Accessibility), `TextInjector` (CGEvent Unicode injection; clears modifiers, key-down-only, fail-closed on secure fields), `SplashWindow` (3 s launch splash; **`isReleasedWhenClosed = false`** — do not remove, it prevents a crash), `Info.plist`, `AppIcon.icns`.
- `scripts/` — `setup-whisper.sh`, `make-app.sh`, `make-signing-cert.sh`, `make-icon.{sh,swift}`, `install.sh`, `install-prebuilt.sh`, `download-model.sh`, `convert-hr-finetune.sh`, `uninstall.sh`, `run-fleurs-matrix.sh`.
- `benchmark/` — Python CER/WER harness (15 pytest pass). `docs/research/phase-1-benchmark-2026-07-03.md`.

## Key decisions (current)
- **Model:** Croatian fine-tune `GoranS/whisper-large-v3-turbo-hr-parla` → GGML q8_0 (`convert-hr-finetune.sh`), **default** (ModelStore prefers it). WER 8.5% (median 7.1%) vs 11.7% stock turbo; 834 MB, keeps English.
- **Language:** default forced **`hr`** (user found `auto` misdetects his English) + a Language menu to switch. `translate=false`.
- **Signing:** stable self-signed (above). **Repo:** public for now.
- Engine whisper.cpp v1.9.1 static Metal (no Core ML); Swift 6.

## Open issues / next steps
1. **Verify v0.1.4 grant persistence** — user is testing that after one re-grant (identity changed ad-hoc→stable), Mic/Accessibility now stick across updates. Confirm on both his machines + a colleague's.
2. **Text-injection quality (task #21):** earlier "types worse / had to paste" was very likely the ad-hoc grant not persisting → `AXIsProcessTrusted` false → clipboard fallback. **Stable signing (v0.1.4) probably resolves it** — retest; if injection still garbles text, the fallback plan is the clipboard-paste method in `TextInjector.swift`.
3. Set the repo **back to private** when the install push is done.
4. **Phase 5 polish:** hotkey rebind + persist language choice in settings; launch-at-login (`SMAppService`); refine double-tap (possible false trigger on rapid Ctrl+C); auto-punctuation.
5. Optional: **Apple Developer ID ($99/yr)** for friction-free distribution to others (double-click without the install script).
6. Deferred: Common Voice HR benchmark; Core ML latency; number-normalization refinement.

## How to resume
Read this + `README.md` + memory (`project_state`, `app_validated_auto_language`). The app is shipping and works; remaining work is verification of the signing fix, Phase-5 polish, and returning the repo to private. Everything is on `makeit-web/WisperLocal` (public) main, latest release v0.1.4.
