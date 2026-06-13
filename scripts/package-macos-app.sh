#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/FocusPet.app"
EXECUTABLE="$ROOT_DIR/.build/debug/FocusPet"
LOCAL_PET_PACKS_ROOT="$ROOT_DIR/external_generated_packs"
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
for RESOURCE_BUNDLE in "$ROOT_DIR"/.build/debug/FocusPet_*.bundle; do
    [[ -d "$RESOURCE_BUNDLE" ]] || continue
    BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
    ln -s "Contents/Resources/$BUNDLE_NAME" "$APP_DIR/$BUNDLE_NAME"
done

if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ "$INCLUDE_LOCAL_TEST_PETS" -eq 1 && -d "$LOCAL_PET_PACKS_ROOT" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/LocalPetPacks"
    for LOCAL_PACK in "$LOCAL_PET_PACKS_ROOT"/*; do
        [[ -d "$LOCAL_PACK" && -f "$LOCAL_PACK/pet.json" ]] || continue
        cp -R "$LOCAL_PACK" "$APP_DIR/Contents/Resources/LocalPetPacks/$(basename "$LOCAL_PACK")"
    done
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
