#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NucLED"
BUNDLE_ID="local.nucled.MenuBar"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="1.0.4"
BUILD_VERSION="5"
VOLUME_NAME="冥王 LED 安装器"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-Installer.dmg"
ICON_SOURCE="$ROOT_DIR/Sources/NucLED/Resources/AppIcon.icns"
ICON_NAME="$APP_NAME.icns"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nucled-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"

"$ROOT_DIR/script/build_app_icon.sh"

echo "Building $APP_NAME (release)…"
swift build --configuration release --package-path "$ROOT_DIR"
BUILD_BIN_DIR="$(swift build --configuration release --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_RESOURCE_BUNDLE="$BUILD_BIN_DIR/NucLED_NucLED.bundle"
if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Build succeeded but executable was not found: $BUILD_BINARY" >&2
  exit 1
fi

echo "Creating app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
install -m 755 "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  ditto "$BUILD_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/NucLED_NucLED.bundle"
fi

if [[ -f "$ICON_SOURCE" ]]; then
  install -m 644 "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/$ICON_NAME"
  ICON_PLIST_ENTRY="  <key>CFBundleIconFile</key><string>$ICON_NAME</string>"
else
  ICON_PLIST_ENTRY=""
  echo "No app icon found at $ICON_SOURCE; packaging without a custom icon."
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>冥王 LED</string>
  <key>CFBundleDisplayName</key><string>冥王 LED</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$ICON_PLIST_ENTRY
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing with configured identity: $CODESIGN_IDENTITY"
  codesign --force --options runtime --timestamp --identifier "$BUNDLE_ID" \
    --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "No Developer ID identity configured; applying an ad-hoc signature for local Service Management support."
  codesign --force --deep --identifier "$BUNDLE_ID" --sign - "$APP_BUNDLE"
  echo "The app is not Developer ID signed or notarized."
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

cp "$ROOT_DIR/script/DMG-INSTALL-README.txt" "$STAGING_DIR/安装说明.txt"
ln -s /Applications "$STAGING_DIR/Applications"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"

rm -f "$DMG_PATH"
echo "Creating drag-to-Applications disk image…"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Created: $DMG_PATH"
