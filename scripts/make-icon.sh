#!/bin/bash
# Generate src/WisperApp/AppIcon.icns from a freshly rendered 1024px icon.
set -e
cd "$(dirname "$0")/.." || exit 1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

swift scripts/make-icon.swift "$TMP/icon-1024.png"

ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" \
            "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$TMP/icon-1024.png" --out "$ICONSET/icon_$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o src/WisperApp/AppIcon.icns
echo "wrote src/WisperApp/AppIcon.icns ($(du -h src/WisperApp/AppIcon.icns | cut -f1))"
