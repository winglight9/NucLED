#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/Sources/NucLED/Resources"
SOURCE_SKULL="$RESOURCE_DIR/HadesSkullColor.png"
ICON_GENERATOR="$ROOT_DIR/script/build_app_icon.swift"
TMP_ROOT="$(mktemp -d -t nucled-icon-XXXXXX)"
MASTER_PNG="$TMP_ROOT/master.png"
ICONSET_DIR="$TMP_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

swift "$ICON_GENERATOR" "$SOURCE_SKULL" "$MASTER_PNG"

make_icon() {
  local points="$1"
  local filename="$2"
  sips -z "$points" "$points" "$MASTER_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCE_DIR/AppIcon.icns"
echo "Created $RESOURCE_DIR/AppIcon.icns"
