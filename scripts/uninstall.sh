#!/bin/bash
# Completely remove WisperLocal: the app, its models, and its app-support data.
# Run: bash scripts/uninstall.sh   (or curl it — see README).
echo "Removing WisperLocal ..."
osascript -e 'quit app "WisperLocal"' 2>/dev/null || true
pkill -x WisperLocal 2>/dev/null || true

rm -rf "/Applications/WisperLocal.app"
rm -rf "$HOME/Library/Application Support/WisperLocal"

echo "Removed:"
echo "  /Applications/WisperLocal.app"
echo "  ~/Library/Application Support/WisperLocal  (models + data)"
echo ""
echo "To also revoke the permissions it was granted:"
echo "  tccutil reset Microphone hr.makeit.wisperlocal"
echo "  tccutil reset Accessibility hr.makeit.wisperlocal"
echo ""
echo "If you had enabled 'Launch at Login', remove the leftover entry in:"
echo "  System Settings → General → Login Items"
