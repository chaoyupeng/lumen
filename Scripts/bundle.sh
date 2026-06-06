#!/usr/bin/env bash
#
# Assemble a self-contained, ad-hoc-signed Lumen.app:
#  - builds the release binary
#  - vendors libmpv + its FULL transitive dylib closure into Contents/Frameworks
#    (recursive otool walker — NOT a hand list), rewriting install names to @rpath
#  - writes Info.plist (min-OS pinned to the bundled libmpv's build target)
#  - ad-hoc code-signs inner-to-outer with the library-validation-disabling
#    entitlement
#
# Portable to macOS's stock bash 3.2 (no associative arrays).
set -euo pipefail

APP_NAME="Lumen"
BUNDLE_ID="com.haizea.lumen"
VERSION="${1:-0.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ENTITLEMENTS="$ROOT/lumen.entitlements"

realpath_py() { /usr/bin/env python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
is_brew() { case "$1" in /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/opt/*) return 0;; *) return 1;; esac; }
deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }

echo "==> swift build -c release"
( cd "$ROOT" && swift build -c release )

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES" "$FRAMEWORKS"
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod u+w "$MACOS/$APP_NAME"

# SwiftPM resource bundle (subdl.py, AppIcon).
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RES/"
fi

# App icon at the bundle's top-level Resources for CFBundleIconFile.
if [ -f "$ROOT/Sources/Lumen/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Sources/Lumen/Resources/AppIcon.icns" "$RES/AppIcon.icns"
fi

# Pin the deployment floor to the bundled libmpv's actual build target.
LIBMPV_REAL="$(realpath_py /opt/homebrew/lib/libmpv.dylib)"
MINOS="$(otool -l "$LIBMPV_REAL" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')"
MINOS="${MINOS:-26.0}"
echo "   bundled libmpv minos = $MINOS"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MINOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.video</string>
        <string>public.audiovisual-content</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> Vendoring dylib closure (recursive)"
# BFS over a queue file; "already copied" == file present in Frameworks/.
QUEUE="$(mktemp)"
echo "$MACOS/$APP_NAME" > "$QUEUE"
while [ -s "$QUEUE" ]; do
  bin="$(head -n 1 "$QUEUE")"
  sed -i '' '1d' "$QUEUE"
  while IFS= read -r dep; do
    is_brew "$dep" || continue
    real="$(realpath_py "$dep")"
    base="$(basename "$real")"
    if [ ! -f "$FRAMEWORKS/$base" ]; then
      cp "$real" "$FRAMEWORKS/$base"
      chmod u+w "$FRAMEWORKS/$base"
      echo "$FRAMEWORKS/$base" >> "$QUEUE"
    fi
  done < <(deps_of "$bin")
done
rm -f "$QUEUE"
echo "   bundled $(ls -1 "$FRAMEWORKS" | wc -l | tr -d ' ') dylibs"

echo "==> Rewriting install names to @rpath"
fix_binary() {
  local bin="$1"
  case "$bin" in "$FRAMEWORKS"/*) install_name_tool -id "@rpath/$(basename "$bin")" "$bin" 2>/dev/null || true;; esac
  while IFS= read -r dep; do
    is_brew "$dep" || continue
    local base; base="$(basename "$(realpath_py "$dep")")"
    install_name_tool -change "$dep" "@rpath/$base" "$bin" 2>/dev/null || true
  done < <(deps_of "$bin")
}
fix_binary "$MACOS/$APP_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true
for dylib in "$FRAMEWORKS"/*.dylib; do fix_binary "$dylib"; done

echo "==> Verifying no Homebrew paths remain"
leak=0
for bin in "$MACOS/$APP_NAME" "$FRAMEWORKS"/*.dylib; do
  if deps_of "$bin" | grep -qE '^(/opt/homebrew|/usr/local/(Cellar|opt))/'; then
    echo "   LEAK: $(basename "$bin")"
    deps_of "$bin" | grep -E '^(/opt/homebrew|/usr/local/(Cellar|opt))/' | sed 's/^/      /'
    leak=1
  fi
done
[ "$leak" -eq 0 ] && echo "   clean (only @rpath/system paths)" || echo "   WARNING: residual Homebrew paths above"

echo "==> Code signing (ad-hoc, inner -> outer)"
for dylib in "$FRAMEWORKS"/*.dylib; do
  codesign -f -s - "$dylib" >/dev/null 2>&1 || true
done
codesign -f -s - --options runtime --entitlements "$ENTITLEMENTS" "$MACOS/$APP_NAME"
codesign -f -s - --options runtime --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP" && echo "   signature valid" || echo "   (codesign --verify reported issues)"

echo "==> Done: $APP"
