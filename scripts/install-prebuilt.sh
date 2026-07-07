#!/bin/bash
# Install WisperLocal from the prebuilt GitHub release — NO developer tools.
# Uses only built-in macOS tools (curl, ditto, xattr). Requires the repo/release
# to be public (temporarily). Run on the target Mac.
set -e
REPO="makeit-web/WisperLocal"
APPZIP="https://github.com/$REPO/releases/latest/download/WisperLocal.app.zip"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Downloading WisperLocal.app ..."
curl -fL "$APPZIP" -o "$TMP/WisperLocal.app.zip"
rm -rf /Applications/WisperLocal.app
ditto -x -k "$TMP/WisperLocal.app.zip" /Applications/
xattr -dr com.apple.quarantine /Applications/WisperLocal.app 2>/dev/null || true

echo "Downloading the model (~834 MB, one time) ..."
MDIR="$HOME/Library/Application Support/WisperLocal/models"
mkdir -p "$MDIR"
if [ ! -f "$MDIR/ggml-large-v3-turbo-q8_0.bin" ]; then
  curl -fL "$MODEL_URL" -o "$MDIR/ggml-large-v3-turbo-q8_0.bin"
fi

cat <<'DONE'

✅ Installed: /Applications/WisperLocal.app  (no build tools used)

Now:
  1. open -a WisperLocal
  2. Grant Microphone when asked.
  3. Grant Accessibility: menu-bar 🎤 -> "Open Accessibility Settings…" -> enable WisperLocal -> quit & relaunch.
  4. Dictate: double-tap Ctrl (or ⌃⌥D), speak, double-tap Ctrl again.
DONE
