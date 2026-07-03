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

echo "Provisioning models into Application Support ..."
MODELS_DIR="$HOME/Library/Application Support/WisperLocal/models"
mkdir -p "$MODELS_DIR"
for m in ggml-large-v3-q8_0.bin ggml-large-v3-turbo-q8_0.bin; do
  if [ -f "models/$m" ] && [ ! -f "$MODELS_DIR/$m" ]; then
    echo "  copying $m"
    cp "models/$m" "$MODELS_DIR/"
  fi
done

echo "Ad-hoc signing ..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "Done: $APP"
echo "Launch it, then grant Microphone permission when prompted. Hotkey: Control+Option+D."
