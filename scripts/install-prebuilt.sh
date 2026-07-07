#!/bin/bash
# Install WisperLocal from the prebuilt GitHub release — NO developer tools.
# Uses only built-in macOS tools (curl, ditto, xattr, shasum). Requires the
# release to be public. Run on the target Mac.
set -e
REPO="makeit-web/WisperLocal"

# Pinned app release + its SHA256. Bump BOTH every release (see docs/DEVELOPMENT.md).
# Pinning + a committed checksum is the integrity boundary: a swapped release
# asset would fail verification instead of silently running on a colleague's Mac.
APP_VERSION="v0.1.6"
APP_ZIP="https://github.com/$REPO/releases/download/$APP_VERSION/WisperLocal.app.zip"
APP_SHA256="f3470524c85f49c981a62646816341d152520d6ac7cd3e33dfccf93b16e01f44"

# Croatian fine-tune model (lives on the v0.1.1 release) + its SHA256.
MODEL_NAME="ggml-hr-parla-q8_0.bin"
MODEL_URL="https://github.com/$REPO/releases/download/v0.1.1/$MODEL_NAME"
MODEL_SHA256="29b73250e1f190bf60fb2394e7b6e76faed417aedbd622bdca6ccb90825be88c"

verify() {  # <file> <expected-sha256> <label>
  local got; got="$(shasum -a 256 "$1" | awk '{print $1}')"
  if [ "$got" != "$2" ]; then
    echo "!! SHA256 mismatch for $3 — refusing to install." >&2
    echo "   expected: $2" >&2
    echo "   got:      $got" >&2
    exit 1
  fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Downloading WisperLocal.app ($APP_VERSION) ..."
curl -fL "$APP_ZIP" -o "$TMP/WisperLocal.app.zip"
verify "$TMP/WisperLocal.app.zip" "$APP_SHA256" "WisperLocal.app.zip"
# Quit any running instance so the app that next launches is the updated one.
osascript -e 'quit app "WisperLocal"' 2>/dev/null || true
pkill -x WisperLocal 2>/dev/null || true
rm -rf /Applications/WisperLocal.app
ditto -x -k "$TMP/WisperLocal.app.zip" /Applications/
xattr -dr com.apple.quarantine /Applications/WisperLocal.app 2>/dev/null || true

echo "Downloading the Croatian model (~834 MB, one time) ..."
MDIR="$HOME/Library/Application Support/WisperLocal/models"
mkdir -p "$MDIR"
if [ ! -f "$MDIR/$MODEL_NAME" ]; then
  curl -fL "$MODEL_URL" -o "$TMP/$MODEL_NAME"
  verify "$TMP/$MODEL_NAME" "$MODEL_SHA256" "$MODEL_NAME"
  mv "$TMP/$MODEL_NAME" "$MDIR/$MODEL_NAME"
fi
# The old general model is redundant once the Croatian fine-tune is present.
[ -f "$MDIR/$MODEL_NAME" ] && rm -f "$MDIR/ggml-large-v3-turbo-q8_0.bin"

cat <<'DONE'

✅ Installed: /Applications/WisperLocal.app  (verified, no build tools used)

Now:
  1. open -a WisperLocal
  2. Grant Microphone when asked.
  3. Grant Accessibility: menu-bar 🎤 -> "Open Accessibility Settings…" -> enable WisperLocal -> quit & relaunch.
  4. Dictate: double-tap Ctrl (or ⌃⌥D), speak, double-tap Ctrl again.
DONE
