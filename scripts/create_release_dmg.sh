#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-"$ROOT_DIR/dist/剪贴板助手.app"}"
DMG_PATH="${2:-"$ROOT_DIR/dist/剪贴板助手.dmg"}"
VOLUME_NAME="剪贴板助手"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"
RW_DMG="$ROOT_DIR/dist/剪贴板助手-rw.dmg"
BACKGROUND_PATH="$ROOT_DIR/Packaging/dmg-background.png"
VOLUME_ICON_PATH="$ROOT_DIR/Packaging/VolumeIcon.icns"

if [ ! -d "$APP_PATH" ]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$RW_DMG" "$DMG_PATH"
mkdir -p "$STAGING_DIR/.background" "$ROOT_DIR/dist"
ditto "$APP_PATH" "$STAGING_DIR/剪贴板助手.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/dmg-background.png"
cp "$VOLUME_ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"

while IFS= read -r -d '' mounted_volume; do
  hdiutil detach "$mounted_volume" -force -quiet || true
done < <(find /Volumes -maxdepth 1 -type d -name "$VOLUME_NAME*" -print0 2>/dev/null)

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | head -n 1)"

if [ -z "$MOUNT_POINT" ]; then
  echo "Could not find mounted volume path." >&2
  echo "$MOUNT_OUTPUT" >&2
  exit 1
fi

cleanup() {
  if [ -n "${MOUNT_POINT:-}" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
}
trap cleanup EXIT

cp "$VOLUME_ICON_PATH" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {140, 120, 860, 560}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set background picture of theViewOptions to POSIX file "$MOUNT_POINT/.background/dmg-background.png"
    set position of item "剪贴板助手.app" of container window to {190, 220}
    set position of item "Applications" of container window to {530, 220}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_POINT" -quiet
trap - EXIT

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR" "$RW_DMG"

echo "created: $DMG_PATH"
