#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/FocusPet.app"
EXECUTABLE="$ROOT_DIR/.build/debug/FocusPet"
RESOURCE_BUNDLE="$ROOT_DIR/.build/debug/FocusPet_FocusPetMac.bundle"
LOCAL_LUO_PACK="$ROOT_DIR/external_generated_packs/LuoXiaoHeiLocal"
APP_ICON="$ROOT_DIR/Sources/FocusPetMac/Resources/AppIcon.icns"
INCLUDE_LOCAL_TEST_PETS=0

for arg in "$@"; do
    if [[ "$arg" == "--include-local-test-pets" ]]; then
        INCLUDE_LOCAL_TEST_PETS=1
    fi
done

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FocusPet"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
    ln -s "Contents/Resources/FocusPet_FocusPetMac.bundle" "$APP_DIR/FocusPet_FocusPetMac.bundle"
fi

if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ "$INCLUDE_LOCAL_TEST_PETS" -eq 1 && -d "$LOCAL_LUO_PACK" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/LocalPetPacks"
    cp -R "$LOCAL_LUO_PACK" "$APP_DIR/Contents/Resources/LocalPetPacks/LuoXiaoHeiLocal"
fi

if [[ "$INCLUDE_LOCAL_TEST_PETS" -eq 0 ]]; then
    echo "Excluding raw local-only source folders..."
    find "$APP_DIR" -name "external_assets" -type d -prune -exec rm -rf {} +
    find "$APP_DIR" -name "external_generated_packs" -type d -prune -exec rm -rf {} +
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>FocusPet</string>
    <key>CFBundleIdentifier</key>
    <string>local.focuspet.v0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Focus Pet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
