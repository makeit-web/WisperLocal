#!/bin/bash
# Install WisperLocal from the prebuilt GitHub release — NO developer tools.
# Uses only built-in macOS tools (curl, ditto, xattr, shasum). Requires the
# release to be public. Run on the target Mac.
set -e
REPO="makeit-web/WisperLocal"

# Pinned app release + its SHA256. Bump BOTH every release (see docs/DEVELOPMENT.md).
# Pinning + a committed checksum is the integrity boundary: a swapped release
# asset would fail verification instead of silently running on a colleague's Mac.
APP_VERSION="v0.1.8"
APP_ZIP="https://github.com/$REPO/releases/download/$APP_VERSION/WisperLocal.app.zip"
APP_SHA256="b325c731d1d0861deadcbc246a1a894b990d8a9ac256531d398edc4d26e37e83"

# Croatian fine-tune model (lives on the v0.1.1 release) + its SHA256.
MODEL_NAME="ggml-hr-parla-q8_0.bin"
MODEL_URL="https://github.com/$REPO/releases/download/v0.1.1/$MODEL_NAME"
MODEL_SHA256="29b73250e1f190bf60fb2394e7b6e76faed417aedbd622bdca6ccb90825be88c"

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

verify() {  # <file> <expected-sha256> <label>
  local got; got="$(sha_of "$1")"
  if [ "$got" != "$2" ]; then
    echo "!! SHA256 mismatch for $3 — refusing to install." >&2
    echo "   expected: $2" >&2
    echo "   got:      $got" >&2
    exit 1
  fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Downloading WisperLocal.app ($APP_VERSION) ..."
curl -fL --retry 5 --retry-all-errors "$APP_ZIP" -o "$TMP/WisperLocal.app.zip"
verify "$TMP/WisperLocal.app.zip" "$APP_SHA256" "WisperLocal.app.zip"
# Stage first, swap last: the old app is deleted only after the new bundle is
# verified AND extracted — a failed download/extract must never strand the
# machine with no app at all.
mkdir -p "$TMP/stage"
ditto -x -k "$TMP/WisperLocal.app.zip" "$TMP/stage"
if [ ! -x "$TMP/stage/WisperLocal.app/Contents/MacOS/WisperLocal" ]; then
  echo "!! Extracted bundle is malformed — refusing to install." >&2
  exit 1
fi
# Quit any running instance so the app that next launches is the updated one.
osascript -e 'quit app "WisperLocal"' 2>/dev/null || true
pkill -x WisperLocal 2>/dev/null || true
# Swap with a restorable backup: if the final mv fails (permissions, disk
# full), put the previous app back instead of leaving the machine with none.
BACKUP="/Applications/WisperLocal.app.previous.$$"
[ -d /Applications/WisperLocal.app ] && mv /Applications/WisperLocal.app "$BACKUP"
if mv "$TMP/stage/WisperLocal.app" /Applications/WisperLocal.app; then
  rm -rf "$BACKUP"
else
  [ -d "$BACKUP" ] && mv "$BACKUP" /Applications/WisperLocal.app
  echo "!! Install failed while swapping the app — previous version restored." >&2
  exit 1
fi
xattr -dr com.apple.quarantine /Applications/WisperLocal.app 2>/dev/null || true

echo "Checking the Croatian model (~834 MB, downloaded once) ..."
MDIR="$HOME/Library/Application Support/WisperLocal/models"
mkdir -p "$MDIR"
# Re-verify a pre-existing model too: a partial/corrupt file from an
# interrupted install must not be trusted forever just because it exists.
if [ -f "$MDIR/$MODEL_NAME" ]; then
  if [ "$(sha_of "$MDIR/$MODEL_NAME")" = "$MODEL_SHA256" ]; then
    echo "  model present (checksum verified)"
  else
    echo "  existing model failed verification — re-downloading"
    rm -f "$MDIR/$MODEL_NAME"
  fi
fi
if [ ! -f "$MDIR/$MODEL_NAME" ]; then
  # --retry + resume (-C -): a Wi-Fi blip must not restart 834 MB from byte 0.
  curl -fL --retry 5 --retry-all-errors -C - "$MODEL_URL" -o "$TMP/$MODEL_NAME"
  verify "$TMP/$MODEL_NAME" "$MODEL_SHA256" "$MODEL_NAME"
  mv "$TMP/$MODEL_NAME" "$MDIR/$MODEL_NAME"
fi
# The old general model is redundant once the Croatian fine-tune is present.
# (The app's fallback chain knows this — ModelStore names the fine-tune when
# nothing else is installed. Keep the two in sync.)
[ -f "$MDIR/$MODEL_NAME" ] && rm -f "$MDIR/ggml-large-v3-turbo-q8_0.bin"

cat <<'DONE'

✅ Installed: /Applications/WisperLocal.app  (verified, no build tools used)

Now:
  1. open -a WisperLocal
  2. Grant Microphone when asked.
  3. Grant Accessibility: menu-bar 🎤 -> "Open Accessibility Settings…" -> enable WisperLocal -> quit & relaunch.
  4. Dictate: double-tap Ctrl (or ⌃⌥D), speak, double-tap Ctrl again.
DONE
