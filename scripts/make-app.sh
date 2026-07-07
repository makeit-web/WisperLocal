#!/bin/bash
# Build WisperLocal.app: a proper .app bundle (Info.plist for TCC) wrapping the
# SwiftPM WisperApp executable, provisioning the RAM-selected model into
# Application Support, and ad-hoc signing it. Run from anywhere.
set -e
cd "$(dirname "$0")/.." || exit 1

DEV="${1:-}"   # pass --dev for a local ad-hoc build; releases MUST be stable-signed
APP="WisperLocal.app"
echo "Building WisperApp (release) ..."
swift build -c release --product WisperApp >/dev/null

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WisperApp "$APP/Contents/MacOS/WisperLocal"
cp src/WisperApp/Info.plist "$APP/Contents/Info.plist"
cp src/WisperApp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Provisioning models into Application Support ..."
MODELS_DIR="$HOME/Library/Application Support/WisperLocal/models"
mkdir -p "$MODELS_DIR"
for m in ggml-hr-parla-q8_0.bin ggml-large-v3-q8_0.bin ggml-large-v3-turbo-q8_0.bin; do
  if [ -f "models/$m" ] && [ ! -f "$MODELS_DIR/$m" ]; then
    echo "  copying $m"
    cp "models/$m" "$MODELS_DIR/"
  fi
done

# Sign with the stable self-signed identity (scripts/make-signing-cert.sh) so
# macOS keeps the Accessibility grant across updates. Sign by hash from the
# dedicated keychain (unambiguous); fall back to ad-hoc if it isn't set up.
SIGN_KC="$HOME/Library/Keychains/wisper-signing.keychain-db"
SIGN_HASH="$(security find-identity -p codesigning "$SIGN_KC" 2>/dev/null | grep -oE '[0-9A-F]{40}' | head -1)"
if [ -n "$SIGN_HASH" ]; then
  # Keychain password read from a local, gitignored file — never hardcoded here.
  SIGN_PW="$(cat "$HOME/.wisperlocal-signing-pw" 2>/dev/null || true)"
  [ -n "$SIGN_PW" ] && security unlock-keychain -p "$SIGN_PW" "$SIGN_KC" 2>/dev/null || true
  if codesign --force --deep --keychain "$SIGN_KC" --sign "$SIGN_HASH" "$APP" >/dev/null 2>&1; then
    echo "  (stable-signed: WisperLocal)"
  elif [ "$DEV" = "--dev" ]; then
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1; echo "  (ad-hoc --dev build)"
  else
    echo "!! Stable signing FAILED — refusing to ship an ad-hoc/unsigned release" >&2
    echo "   (it would reset every user's Accessibility/Mic grant). Fix the signing" >&2
    echo "   keychain (scripts/make-signing-cert.sh), or run with --dev for a local build." >&2
    exit 1
  fi
elif [ "$DEV" = "--dev" ]; then
  echo "Ad-hoc --dev signing (no stable identity present) ..."
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
else
  echo "!! No stable signing identity — refusing to build an unsigned release." >&2
  echo "   Run scripts/make-signing-cert.sh once, or pass --dev for a local ad-hoc build." >&2
  exit 1
fi

# Privacy guard (Swift Quality Profile §30): the app is non-sandboxed, so egress
# can only be assured by inspecting the built binary. Hard-fail if it imports or
# links any networking symbol — nothing in WisperLocal should touch the network.
BIN="$APP/Contents/MacOS/WisperLocal"
if nm -u "$BIN" 2>/dev/null | grep -qiE "CFNetwork|NSURLSession|nw_connection|nw_endpoint|getaddrinfo|curl_easy"; then
  echo "!! EGRESS SCAN FAILED — a networking symbol is imported by the binary. Refusing to ship." >&2
  nm -u "$BIN" | grep -iE "CFNetwork|NSURLSession|nw_connection|nw_endpoint|getaddrinfo|curl_easy" >&2
  exit 1
fi
if otool -L "$BIN" 2>/dev/null | grep -qiE "CFNetwork|/Network\.framework|libcurl"; then
  echo "!! EGRESS SCAN FAILED — a networking framework is linked. Refusing to ship." >&2
  exit 1
fi
echo "  (egress scan: clean — no networking symbols)"

echo "Done: $APP"
echo "Launch it, then grant Microphone permission when prompted. Hotkey: Control+Option+D."
