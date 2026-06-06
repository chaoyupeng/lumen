#!/usr/bin/env bash
# Package dist/Lumen.app into a compressed DMG with an /Applications shortcut.
set -euo pipefail

APP_NAME="Lumen"
VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

[ -d "$APP" ] || { echo "No $APP — run 'make bundle' first."; exit 1; }

rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "==> $DMG"
