#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc Tools/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP"
cp "$TMP/DictatoLogo.png" Resources/DictatoLogo.png

SET="$TMP/Dictato.iconset"
mkdir -p "$SET"
SRC="$TMP/icon-1024.png"
for s in 16 32 64 128 256 512 1024; do
    sips -z $s $s "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
done
# @2x variants
cp "$SET/icon_32x32.png"   "$SET/icon_16x16@2x.png"
cp "$SET/icon_64x64.png"   "$SET/icon_32x32@2x.png"
cp "$SET/icon_256x256.png" "$SET/icon_128x128@2x.png"
cp "$SET/icon_512x512.png" "$SET/icon_256x256@2x.png"
cp "$SET/icon_1024x1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o Resources/Dictato.icns
echo "wrote Resources/Dictato.icns + Resources/DictatoLogo.png"
