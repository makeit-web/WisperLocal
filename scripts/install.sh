#!/bin/bash
# One-command install for a fresh Mac (run from inside the cloned repo):
#   git clone git@github.com:makeit-web/WisperLocal.git && cd WisperLocal && bash scripts/install.sh
# Builds whisper.cpp, downloads the RAM-appropriate model, builds WisperLocal.app,
# and installs it to /Applications. Idempotent.
set -e
cd "$(dirname "$0")/.." || exit 1

echo "== WisperLocal install =="

# 1. Prerequisites (the two interactive ones must be installed by hand).
if ! xcode-select -p >/dev/null 2>&1; then
  echo "!! Xcode Command Line Tools required (the ~2 GB CLT, NOT full Xcode). Run: xcode-select --install  (then re-run this)."
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "!! Homebrew required. Install from https://brew.sh (then re-run this)."
  exit 1
fi
command -v cmake >/dev/null 2>&1 || { echo "Installing cmake ..."; HOMEBREW_NO_AUTO_UPDATE=1 brew install cmake; }

# 2. Build whisper.cpp (static, Metal) + stage headers.
bash scripts/setup-whisper.sh

# 3. Download the RAM-appropriate model.
bash scripts/download-model.sh

# 4. Build WisperLocal.app + provision the model into Application Support.
#    --dev: a from-source build on someone else's Mac has no stable identity, so
#    ad-hoc signing is expected here (only official RELEASES must be stable-signed).
bash scripts/make-app.sh --dev

# 5. Install to /Applications. Quit any running instance first — replacing the
#    bundle under a live process leaves the user silently on the old version
#    (and can wedge TCC until relaunch). Same block as install-prebuilt.sh.
echo "Installing to /Applications ..."
osascript -e 'quit app "WisperLocal"' 2>/dev/null || true
pkill -x WisperLocal 2>/dev/null || true
rm -rf /Applications/WisperLocal.app
cp -R WisperLocal.app /Applications/

cat <<'DONE'

✅ Installed: /Applications/WisperLocal.app

Next (one time):
  1. open -a WisperLocal
  2. Grant Microphone when asked.
  3. Grant Accessibility: menu-bar 🎤 -> "Open Accessibility Settings…" -> enable WisperLocal, then quit & relaunch.
  4. Dictate: double-tap Ctrl (or ⌃⌥D), speak, double-tap Ctrl again. Text types where your cursor is.

Optional (stable permission across rebuilds): bash scripts/make-signing-cert.sh  (click "Always Allow"), then re-run this installer.
DONE
