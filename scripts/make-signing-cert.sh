#!/bin/bash
# Create a STABLE self-signed code-signing identity in a DEDICATED keychain, so
# every release is signed with the same identity and macOS remembers the
# Accessibility / Input-Monitoring grant across updates. Self-contained: the
# keychain has its own password, so this needs no login password and no prompts.
# Run once on the build machine; make-app.sh then signs with it automatically.
set -e
NAME="WisperLocal"
KC_NAME="wisper-signing.keychain"
KC="$HOME/Library/Keychains/wisper-signing.keychain-db"
PW_FILE="$HOME/.wisperlocal-signing-pw"
# Keychain password: random, stored ONLY in a local gitignored file — never in
# the repo. MUST stay hex (no quotes/backslashes/spaces): the `security -i`
# stdin batches below and in make-app.sh re-tokenize the -p/-k arguments with
# security's own parser, which a special character would silently break.
if [ -f "$PW_FILE" ]; then KCPW="$(cat "$PW_FILE")"; else KCPW="$(openssl rand -hex 24)"; printf '%s' "$KCPW" >"$PW_FILE"; chmod 600 "$PW_FILE"; fi
P12PW="$(openssl rand -hex 12)"   # ephemeral p12 transport password (temp file, deleted on exit)

if security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
  echo "Stable identity '$NAME' already set up."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Generating self-signed code-signing certificate ..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
LEGACY=""; openssl version 2>/dev/null | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$P12PW"

echo "Creating a dedicated signing keychain ..."
# Passwords are fed via stdin (`security -i`), never as -p/-P/-k argv — on a
# shared machine `ps` exposes every process's argv to other local users.
security -i 2>/dev/null <<EOF || true
create-keychain -p "$KCPW" "$KC_NAME"
EOF
security set-keychain-settings "$KC_NAME"            # no auto-lock
security -i >/dev/null <<EOF
unlock-keychain -p "$KCPW" "$KC_NAME"
import "$TMP/id.p12" -P "$P12PW" -T /usr/bin/codesign -k "$KC"
set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC"
EOF
# `security -i` swallows per-command failures, so verify the import landed.
security find-identity -p codesigning "$KC" | grep -q "$NAME" || {
  echo "!! Signing identity did not import — keychain setup failed." >&2
  exit 1
}
# Make codesign find the identity by adding the keychain to the search list.
EXISTING=$(security list-keychains -d user | sed -e 's/["[:space:]]//g')
security list-keychains -d user -s "$KC" $EXISTING

echo "Stable identity '$NAME' ready. Re-run scripts/make-app.sh (or the release build)."
