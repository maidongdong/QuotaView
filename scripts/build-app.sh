#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
OUTPUT_APP="$ROOT_DIR/outputs/CodexQuotaBar.app"
OUTPUT_ZIP="$ROOT_DIR/outputs/CodexQuotaBar.zip"
OUTPUT_DMG="$ROOT_DIR/outputs/CodexQuotaBar.dmg"
OUTPUT_DIR="$ROOT_DIR/outputs"
STAGE_DIR=$(mktemp -d /private/tmp/CodexQuotaBar.XXXXXX)
APP_DIR="$STAGE_DIR/CodexQuotaBar.app"
STAGE_ZIP="$STAGE_DIR/CodexQuotaBar.zip"
STAGE_DMG="$STAGE_DIR/CodexQuotaBar.dmg"
DMG_ROOT="$STAGE_DIR/dmg-root"
MOUNT_DIR="$STAGE_DIR/mount"
ICONSET_DIR="$STAGE_DIR/AppIcon.iconset"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon-1024.png"
ICON_RESOURCE="$ROOT_DIR/Resources/AppIcon.icns"
ICON_FILE="$STAGE_DIR/AppIcon.icns"
CONTENTS_DIR="$APP_DIR/Contents"
MOUNTED=0

cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT_DIR" -quiet || true
    fi
    rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"
if [[ "${SKIP_SWIFT_BUILD:-0}" != "1" ]]; then
    swift build -c release
fi
[[ -x ".build/release/CodexQuotaBar" ]]

[[ -f "$ICON_SOURCE" ]]
[[ "$(sips -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth/ { print $2 }')" == "1024" ]]
[[ "$(sips -g pixelHeight "$ICON_SOURCE" | awk '/pixelHeight/ { print $2 }')" == "1024" ]]
[[ -s "$ICON_RESOURCE" ]]

mkdir -p \
    "$CONTENTS_DIR/MacOS" \
    "$CONTENTS_DIR/Resources" \
    "$DMG_ROOT" \
    "$MOUNT_DIR" \
    "$ICONSET_DIR"

cp "$ICON_RESOURCE" "$ICON_FILE"

cp ".build/release/CodexQuotaBar" "$CONTENTS_DIR/MacOS/CodexQuotaBar"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICON_FILE" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$CONTENTS_DIR/MacOS/CodexQuotaBar"

[[ "$(defaults read "$CONTENTS_DIR/Info" CFBundleIdentifier)" == "com.maidongdong.CodexQuotaBar" ]]
[[ "$(defaults read "$CONTENTS_DIR/Info" CFBundleIconFile)" == "AppIcon" ]]
[[ -s "$CONTENTS_DIR/Resources/AppIcon.icns" ]]
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
[[ "$(lipo -archs "$CONTENTS_DIR/MacOS/CodexQuotaBar")" == "arm64" ]]

/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$STAGE_ZIP"
cp -R "$APP_DIR" "$DMG_ROOT/CodexQuotaBar.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
    -volname "Codex 额度栏" \
    -srcfolder "$DMG_ROOT" \
    -format UDZO \
    -ov \
    "$STAGE_DMG" >/dev/null
hdiutil verify "$STAGE_DMG" >/dev/null

hdiutil attach \
    "$STAGE_DMG" \
    -readonly \
    -nobrowse \
    -mountpoint "$MOUNT_DIR" \
    -quiet
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_DIR/CodexQuotaBar.app"
[[ "$(lipo -archs "$MOUNT_DIR/CodexQuotaBar.app/Contents/MacOS/CodexQuotaBar")" == "arm64" ]]
[[ -s "$MOUNT_DIR/CodexQuotaBar.app/Contents/Resources/AppIcon.icns" ]]
[[ "$(defaults read "$MOUNT_DIR/CodexQuotaBar.app/Contents/Info" CFBundleIconFile)" == "AppIcon" ]]
[[ -L "$MOUNT_DIR/Applications" ]]
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]]
hdiutil detach "$MOUNT_DIR" -quiet
MOUNTED=0

rm -rf "$OUTPUT_APP"
cp -R "$APP_DIR" "$OUTPUT_APP"
xattr -cr "$OUTPUT_APP"
codesign --force --deep --sign - "$OUTPUT_APP"
codesign --verify --deep --strict "$OUTPUT_APP"
cp "$STAGE_ZIP" "$OUTPUT_ZIP"
cp "$STAGE_DMG" "$OUTPUT_DMG"
unzip -tq "$OUTPUT_ZIP"
hdiutil verify "$OUTPUT_DMG" >/dev/null

echo "$OUTPUT_APP"
echo "$OUTPUT_ZIP"
echo "$OUTPUT_DMG"
