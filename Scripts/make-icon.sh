#!/usr/bin/env bash
# Generate Resources/AppIcon.png + AppIcon.icns from Core Graphics drawing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/Sources/Lumen/Resources"
PNG="$RES/AppIcon.png"

swift "$ROOT/Scripts/make-icon.swift" "$PNG"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16   "$PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 "$PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$PNG" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
echo "wrote $RES/AppIcon.icns"
