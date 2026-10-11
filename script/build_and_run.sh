#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NucLED"
BUNDLE_ID="local.nucled.MenuBar"
MIN_SYSTEM_VERSION="13.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Sources/NucLED/Resources/AppIcon.icns"
ICON_NAME="$APP_NAME.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/script/build_app_icon.sh"
swift build
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_RESOURCE_BUNDLE="$BUILD_BIN_DIR/NucLED_NucLED.bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_CONTENTS/Resources/$ICON_NAME"
if [[ -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  ditto "$BUILD_RESOURCE_BUNDLE" "$APP_CONTENTS/Resources/NucLED_NucLED.bundle"
fi
for locale in zh-Hans en ja ko; do
  localized_plist="$ROOT_DIR/Sources/NucLED/Resources/$locale.lproj/InfoPlist.strings"
  if [[ -f "$localized_plist" ]]; then
    mkdir -p "$APP_CONTENTS/Resources/$locale.lproj"
    cp "$localized_plist" "$APP_CONTENTS/Resources/$locale.lproj/InfoPlist.strings"
  fi
done
cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>冥王 LED</string>
  <key>CFBundleDisplayName</key><string>冥王 LED</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleLocalizations</key>
  <array><string>zh-Hans</string><string>en</string><string>ja</string><string>ko</string></array>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleIconFile</key><string>$ICON_NAME</string>
</dict>
</plist>
PLIST
open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
