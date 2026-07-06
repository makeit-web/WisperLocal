#!/bin/bash
# Create a STABLE self-signed code-signing identity "WisperLocal" in your login
# keychain (ADR-005). Run this ONCE — you may be asked for your login password.
# A stable identity lets macOS remember the Accessibility / Input-Monitoring
# grant across rebuilds, so text injection and the double-tap hotkey keep working
# without re-granting every time. After this, run scripts/make-app.sh again.
set -e
NAME="WisperLocal"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Code-signing identity '$NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Generating a self-signed code-signing certificate ..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# OpenSSL 3 defaults to a PKCS12 MAC that macOS cannot import; use -legacy there.
LEGACY=""
openssl version 2>/dev/null | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -name "$NAME" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:wisper

echo "Importing into the login keychain (you may be prompted) ..."
security import "$TMP/id.p12" -P wisper -A -T /usr/bin/codesign \
  -k "$HOME/Library/Keychains/login.keychain-db"

echo "Done. Identity '$NAME' created. Now run: bash scripts/make-app.sh"
