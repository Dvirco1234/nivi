#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc Tools/rasterize.swift -o "$TMP/raster"

# Overlay / brand logos (colored), per language
"$TMP/raster" Resources/AppIcon.svg           Resources/DictatoLogo.png    256   # Hebrew (aleph)
"$TMP/raster" Resources/DictationIconLatinA.svg Resources/DictatoLogoEn.png 256   # English (Latin A)

# Menu-bar glyphs (template, tinted by macOS), per language — aspect preserved
"$TMP/raster" Resources/MenuBarAleph.svg  Resources/MenuBarAleph.png  88
"$TMP/raster" Resources/MenuBarLatinA.svg Resources/MenuBarLatinA.png 88

# App icon (.icns) from the aleph app icon
"$TMP/raster" Resources/AppIcon.svg "$TMP/icon-1024.png" 1024
SET="$TMP/Dictato.iconset"
mkdir -p "$SET"
SRC="$TMP/icon-1024.png"
for s in 16 32 64 128 256 512 1024; do
    sips -z $s $s "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
done
cp "$SET/icon_32x32.png"   "$SET/icon_16x16@2x.png"
cp "$SET/icon_64x64.png"   "$SET/icon_32x32@2x.png"
cp "$SET/icon_256x256.png" "$SET/icon_128x128@2x.png"
cp "$SET/icon_512x512.png" "$SET/icon_256x256@2x.png"
cp "$SET/icon_1024x1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o Resources/Dictato.icns
echo "wrote Dictato.icns + DictatoLogo.png (He) + DictatoLogoEn.png + MenuBar{Aleph,LatinA}.png"
