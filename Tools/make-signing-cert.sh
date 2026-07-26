#!/usr/bin/env bash
# Creates a STABLE self-signed code-signing identity "Dictato Self-Signed".
# Signing with a stable identity (instead of ad-hoc "-") keeps macOS TCC grants
# (Accessibility, Microphone) across rebuilds — ad-hoc re-signing revokes them.
set -euo pipefail

NAME="Dictato Self-Signed"
# Capture first, then match. Piping into `grep -q` exits on first match, sending
# SIGPIPE to `security`, which trips `set -o pipefail` and makes this idempotency
# check fail with 141 instead of returning cleanly.
EXISTING=$(security find-identity -v -p codesigning 2>/dev/null || true)
if printf '%s' "$EXISTING" | grep -F "$NAME" >/dev/null 2>&1; then
    echo "Identity '$NAME' already exists."
    exit 0
fi

TMP=$(mktemp -d)
openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 -out "$TMP/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:dictato -legacy -macalg sha1
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P dictato -T /usr/bin/codesign -A
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMP/cert.pem"
rm -rf "$TMP"
echo "Created identity '$NAME'."
