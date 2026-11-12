#!/bin/zsh
# Builds Dusk Wallpaper and installs it into /Applications. Needs only Xcode's command-line tools (swiftc, codesign).
#
#   ./build.sh              build, replace the installed app, restart it quietly
#   ./build.sh --dev DIR    build a separate test copy into DIR (its own settings; never installed or launched)
#
# The app is compiled into a temporary folder first, so a compile error leaves the installed app untouched.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Dusk Wallpaper"
ID="local.dusk.wallpaper"
DEST="/Applications"
MIN_MACOS="14.0"
DEV=0
if [[ "${1:-}" == "--dev" ]]; then DEV=1; DEST="${2:?usage: build.sh --dev DIR}"; ID="$ID.dev"; mkdir -p "$DEST"; fi

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
  <key>CFBundleShortVersionString</key><string>2.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF

# Locally built apps on Apple silicon need a signature; an ad-hoc one uses no certificate, so nothing in it can expire.
codesign --force -s - "$APP"
codesign --verify --strict "$APP"

if [[ $DEV == 0 ]]; then                      # stop the running copy and wait until it is really gone
  pkill -x DuskWallpaper || true
  for i in {1..50}; do pgrep -x DuskWallpaper >/dev/null || break; sleep 0.1; done
fi
rm -rf "$DEST/$NAME.app"
mv "$APP" "$DEST/"
rmdir "$STAGE"
echo "Built $DEST/$NAME.app"
if [[ $DEV == 0 ]]; then                      # start it again without opening the settings window
  for i in {1..5}; do open "$DEST/$NAME.app" --args --background 2>/dev/null && break; sleep 1; done
  sleep 1
  pgrep -x DuskWallpaper >/dev/null || { echo "The app was installed but did not start; open it from Applications." >&2; exit 1; }
fi
