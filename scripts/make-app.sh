#!/bin/bash
# Build WisperLocal.app: a proper .app bundle (Info.plist for TCC) wrapping the
# SwiftPM WisperApp executable, provisioning the RAM-selected model into
# Application Support, and ad-hoc signing it. Run from anywhere.
set -e
cd "$(dirname "$0")/.." || exit 1

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
for m in ggml-large-v3-q8_0.bin ggml-large-v3-turbo-q8_0.bin; do
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
  security unlock-keychain -p wisper-signing "$SIGN_KC" 2>/dev/null || true
  if codesign --force --deep --keychain "$SIGN_KC" --sign "$SIGN_HASH" "$APP" >/dev/null 2>&1; then
    echo "  (stable-signed: WisperLocal)"
  else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1; echo "  (ad-hoc fallback)"
  fi
else
  echo "Ad-hoc signing (run scripts/make-signing-cert.sh once for stable grants) ..."
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

echo "Done: $APP"
echo "Launch it, then grant Microphone permission when prompted. Hotkey: Control+Option+D."
