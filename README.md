# WisperLocal

Local, 100% offline macOS dictation for Apple Silicon. Global hotkey → speak (Croatian or English) → the text is typed into whatever app your cursor is in. Built with whisper.cpp + Swift. Personal use.

## Install on a new Mac (one command)

**Prerequisites** (install these first if missing):
- **Xcode Command Line Tools** — `xcode-select --install` (this is the **~2 GB** developer tools, **NOT** the 15 GB Xcode app — you do not need full Xcode)
- **Homebrew** — https://brew.sh
- **GitHub access** to `makeit-web/WisperLocal` (ssh key or `gh auth login`)

Then, in Terminal:

```bash
git clone git@github.com:makeit-web/WisperLocal.git ~/WisperLocal && cd ~/WisperLocal && bash scripts/install.sh
```

That builds whisper.cpp, downloads the **RAM-appropriate model** (turbo q8_0 on an 8 GB Mac, large-v3 q8_0 on 16 GB+), builds the app, and installs **`/Applications/WisperLocal.app`**. Downloads ~1–3 GB, takes a few minutes.

*(No ssh key? Use `gh repo clone makeit-web/WisperLocal ~/WisperLocal` instead of the `git clone` part.)*

### No build tools at all (prebuilt app)
While the repo is public, on the target Mac — needs **no Command Line Tools, no compiler**:
```bash
curl -fL https://raw.githubusercontent.com/makeit-web/WisperLocal/main/scripts/install-prebuilt.sh -o /tmp/wl-install.sh && bash /tmp/wl-install.sh
```
Downloads the prebuilt `WisperLocal.app` + the model (turbo q8_0) using only built-in macOS tools.

## First run (grant two permissions)
1. `open -a WisperLocal` — a 🎤 appears in the menu bar.
2. **Microphone** — allow when prompted.
3. **Accessibility** — menu-bar 🎤 → *Open Accessibility Settings…* → enable **WisperLocal** → **quit & relaunch** the app.

To stop macOS re-asking for Accessibility after every rebuild, run once and click **"Always Allow"**:
```bash
bash scripts/make-signing-cert.sh && bash scripts/install.sh
```

## Use
- **Double-tap Ctrl** (or **⌃⌥D**) to start, speak, then again to stop. The text types where your cursor is.
- Menu bar → **Language**: Croatian (default) / English / Auto-detect.
- Icons: 🎤 ready · 🔴 recording · ⏳ transcribing · 🔒 secure field (won't type) · 🔐 needs Accessibility.

## Update to the latest version
```bash
cd ~/WisperLocal && git pull && bash scripts/install.sh
```

## Uninstall
Removes the app, its models, and its data:
```bash
curl -fL https://raw.githubusercontent.com/makeit-web/WisperLocal/main/scripts/uninstall.sh -o /tmp/wl-uninstall.sh && bash /tmp/wl-uninstall.sh
```
(The models live in `~/Library/Application Support/WisperLocal/`, separate from the app — dragging the app to Trash does not remove them.)

## Develop / rebuild
```bash
bash scripts/setup-whisper.sh    # build whisper.cpp static (once)
swift build && swift test        # WisperCore (whisper bridge, tested)
bash scripts/make-app.sh         # build WisperLocal.app locally
.build/debug/wisper-cli file whisper.cpp/samples/jfk.wav --lang auto   # CLI
```

## More
- Build, architecture, signing & release process: **`docs/DEVELOPMENT.md`**
- User guides: `docs/UPUTE-HR.md` (hrvatski) / `docs/GUIDE-EN.md` (English)
- Approved plan: `docs/specs/2026-07-02-wisperlocal-master-plan.md`
- Benchmark: `docs/research/phase-1-benchmark-2026-07-03.md`
