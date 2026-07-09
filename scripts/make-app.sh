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
# Model names + RAM tier are re-encoded in: src/WisperCore/ModelStore.swift,
# scripts/download-model.sh, scripts/install-prebuilt.sh — keep all in sync.
# cp -c = APFS clonefile: instant, zero extra disk on the same volume (the
# 8 GB Airs this targets); falls back to a real copy across volumes.
for m in ggml-hr-parla-q8_0.bin ggml-large-v3-q8_0.bin ggml-large-v3-turbo-q8_0.bin; do
  if [ -f "models/$m" ] && [ ! -f "$MODELS_DIR/$m" ]; then
    echo "  copying $m"
    cp -c "models/$m" "$MODELS_DIR/" 2>/dev/null || cp "models/$m" "$MODELS_DIR/"
  fi
done

# Sign with the stable self-signed identity (scripts/make-signing-cert.sh) so
# macOS keeps the Accessibility grant across updates. Sign by hash from the
# dedicated keychain (unambiguous); fall back to ad-hoc if it isn't set up.
# --options runtime (hardened runtime) on every path: without it any same-user
# process can DYLD-inject a dylib and inherit the app's Microphone +
# Accessibility TCC grants — the canonical macOS TCC-piggyback vector. It
# needs no notarization and works with self-signed/ad-hoc identities; the app
# is statically linked, so library validation cannot break loading.
# The entitlements file is MANDATORY with hardened runtime: without
# com.apple.security.device.audio-input the runtime denies the microphone
# outright (no TCC prompt, permanent 🚫) — Quality Review of 2026-07-08.
ENTITLEMENTS="src/WisperApp/WisperLocal.entitlements"
SIGN_KC="$HOME/Library/Keychains/wisper-signing.keychain-db"
SIGN_HASH="$(security find-identity -p codesigning "$SIGN_KC" 2>/dev/null | grep -oE '[0-9A-F]{40}' | head -1)"
if [ -n "$SIGN_HASH" ]; then
  # Keychain password read from a local, gitignored file — never hardcoded
  # here, and fed via stdin (`security -i`) so it never appears in argv,
  # which `ps` exposes to other local users.
  SIGN_PW="$(cat "$HOME/.wisperlocal-signing-pw" 2>/dev/null || true)"
  if [ -n "$SIGN_PW" ]; then
    security -i 2>/dev/null <<EOF || true
unlock-keychain -p "$SIGN_PW" "$SIGN_KC"
EOF
  fi
  if codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --keychain "$SIGN_KC" --sign "$SIGN_HASH" "$APP" >/dev/null 2>&1; then
    echo "  (stable-signed: WisperLocal, hardened runtime)"
  elif [ "$DEV" = "--dev" ]; then
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null 2>&1; echo "  (ad-hoc --dev build)"
  else
    echo "!! Stable signing FAILED — refusing to ship an ad-hoc/unsigned release" >&2
    echo "   (it would reset every user's Accessibility/Mic grant). Fix the signing" >&2
    echo "   keychain (scripts/make-signing-cert.sh), or run with --dev for a local build." >&2
    exit 1
  fi
elif [ "$DEV" = "--dev" ]; then
  echo "Ad-hoc --dev signing (no stable identity present) ..."
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
else
  echo "!! No stable signing identity — refusing to build an unsigned release." >&2
  echo "   Run scripts/make-signing-cert.sh once, or pass --dev for a local ad-hoc build." >&2
  exit 1
fi

# Hard-verify the hardened runtime actually landed (a silently soft signature
# would quietly reopen the DYLD-injection hole on the next release).
if ! codesign -d --verbose=2 "$APP" 2>&1 | grep -qE "flags=.*runtime"; then
  echo "!! Signature lacks the hardened-runtime flag — refusing to ship." >&2
  exit 1
fi
if ! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.device.audio-input"; then
  echo "!! Signature lacks the audio-input entitlement — hardened runtime would" >&2
  echo "   deny the microphone (no prompt, permanent 🚫). Refusing to ship." >&2
  exit 1
fi

# Privacy guard (Swift Quality Profile §30): the app is non-sandboxed, so egress
# can only be assured by inspecting the built binary. Hard-fail if it imports or
# links any networking symbol — nothing in WisperLocal should touch the network.
BIN="$APP/Contents/MacOS/WisperLocal"
# High-level APIs plus the legacy/CF stream layer (NSURLConnection, CFSocket,
# CFStreamCreatePairWithSocket*, getStreamsToHost). Raw BSD syscall names
# (_socket/_connect/...) are deliberately NOT matched — they false-positive on
# libSystem symbols present in every macOS binary.
EGRESS_RE="CFNetwork|NSURLSession|NSURLConnection|nw_connection|nw_endpoint|getaddrinfo|curl_easy|CFSocket|CFStreamCreatePairWithSocket|getStreamsToHost"
if nm -u "$BIN" 2>/dev/null | grep -qiE "$EGRESS_RE"; then
  echo "!! EGRESS SCAN FAILED — a networking symbol is imported by the binary. Refusing to ship." >&2
  nm -u "$BIN" | grep -iE "$EGRESS_RE" >&2
  exit 1
fi
if otool -L "$BIN" 2>/dev/null | grep -qiE "CFNetwork|/Network\.framework|libcurl"; then
  echo "!! EGRESS SCAN FAILED — a networking framework is linked. Refusing to ship." >&2
  exit 1
fi
echo "  (egress scan: clean — no networking symbols)"

echo "Done: $APP"
echo "Launch it, then grant Microphone permission when prompted. Hotkey: Control+Option+D."
