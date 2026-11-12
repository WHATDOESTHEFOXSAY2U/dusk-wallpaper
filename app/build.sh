#!/bin/zsh
# Builds Dusk Wallpaper. Needs only Xcode's command-line tools (swiftc, codesign).
#
#   ./build.sh              build, replace the copy in /Applications, restart it quietly
#   ./build.sh --dmg FILE   build, and pack the app into a disk image to install on another Mac
#   ./build.sh --dev DIR    build a separate test copy into DIR (its own settings; never installed or launched)
#
# The app is compiled into a temporary folder first, so a compile error leaves the installed app untouched.
set -euo pipefail

NAME="Dusk Wallpaper"
ID="local.dusk.wallpaper"
DEST="/Applications"
MIN_MACOS="14.0"
MODE="${1:-install}"
case "$MODE" in
  install) ;;
  --dmg) DMG="${2:?usage: build.sh --dmg FILE}"; DMG="${DMG:a}" ;;
  --dev) DEST="${2:?usage: build.sh --dev DIR}"; DEST="${DEST:a}"; ID="$ID.dev"; mkdir -p "$DEST" ;;
  *) echo "usage: build.sh [--dmg FILE | --dev DIR]" >&2; exit 2 ;;
esac
cd "$(dirname "$0")"

STAGE="$(mktemp -d)"
APP="$STAGE/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -swift-version 6 -O -target "arm64-apple-macos$MIN_MACOS" main.swift -o "$APP/Contents/MacOS/DuskWallpaper"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>DuskWallpaper</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.2</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF

# Locally built apps on Apple silicon need a signature; an ad-hoc one uses no certificate, so nothing in it can expire.
codesign --force -s - "$APP"
codesign --verify --strict "$APP"

if [[ $MODE == --dmg ]]; then                 # the app beside a shortcut to Applications: open, drag across, done
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -ov -volname "$NAME" -srcfolder "$STAGE" -format UDZO "$DMG"
  rm -rf "$STAGE"
  echo "Wrote $DMG"
  exit 0
fi

if [[ $MODE == install ]]; then               # stop the running copy and wait until it is really gone
  pkill -x DuskWallpaper || true
  for i in {1..50}; do pgrep -x DuskWallpaper >/dev/null || break; sleep 0.1; done
fi
rm -rf "$DEST/$NAME.app"
mv "$APP" "$DEST/"
rmdir "$STAGE"
echo "Built $DEST/$NAME.app"
if [[ $MODE == install ]]; then               # start it again without opening the settings window
  for i in {1..5}; do open "$DEST/$NAME.app" --args --background 2>/dev/null && break; sleep 1; done
  sleep 1
  pgrep -x DuskWallpaper >/dev/null || { echo "The app was installed but did not start; open it from Applications." >&2; exit 1; }
fi
