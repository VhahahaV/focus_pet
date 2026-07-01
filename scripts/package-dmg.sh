#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SCRIPT="$ROOT_DIR/scripts/package-macos-app.sh"
WIDGET_VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-widget-extension.sh"
DIST_DIR="$ROOT_DIR/dist"
LOCAL_DIST_DIR="$DIST_DIR/local"
WORK_DIR="$ROOT_DIR/.build/dmg"
STAGING_DIR="$WORK_DIR/staging"
BACKGROUND_PNG="$STAGING_DIR/.background/background.png"
DMG_BACKGROUND_ASSET="$ROOT_DIR/scripts/dmg-assets/background.png"
VOLUME_NAME="Focus Pet Installer"
WINDOW_WIDTH=720
WINDOW_HEIGHT=460
VERIFY=1
MODE="distribution"
PET_PACK_MODE_SET=0
INCLUDE_LOCAL_TEST_PETS_EFFECTIVE=0
EXPECTED_LOCAL_PET_PACK_DIRS=(
    "LuoXiaoHeiLocal"
    "PixelCatMemeLocal"
    "XiaoDaiLocal"
)

SIGN_IDENTITY="${FOCUSPET_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
NOTARY_PROFILE="${FOCUSPET_NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}"
NOTARY_APPLE_ID="${FOCUSPET_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
NOTARY_TEAM_ID="${FOCUSPET_NOTARY_TEAM_ID:-${TEAM_ID:-}}"
NOTARY_PASSWORD="${FOCUSPET_NOTARY_PASSWORD:-${APP_SPECIFIC_PASSWORD:-}}"
APP_ARGS=(--configuration release)

usage() {
    cat <<'USAGE'
Usage: scripts/package-dmg.sh [options]

By default this builds a signed, notarized, stapled distribution DMG that is safe
to upload and download on another Mac. Use --local for a non-notarized smoke-test
image; local images are written under dist/local/ and must not be distributed.
Local and distribution modes exclude external_generated_packs by default so
third-party pet assets are not bundled into the DMG. Pass
--include-local-test-pets only for internal pet-pack smoke testing.

Options:
  --local                         Build a local-only DMG with ad-hoc signing
  --distribution                  Build the uploadable signed/notarized DMG. Default
  --skip-verify                   Skip mount/signature verification
  --sign-identity IDENTITY        Developer ID Application signing identity
  --notary-profile PROFILE        notarytool keychain profile
  --apple-id EMAIL                Apple ID for notarytool
  --team-id TEAMID                Apple Developer Team ID for notarytool
  --password PASSWORD             App-specific password for notarytool
  --bundle-identifier ID          Forward to package-macos-app.sh
  --widget-bundle-identifier ID   Forward to package-macos-app.sh
  --version VERSION               Forward to package-macos-app.sh
  --build BUILD                   Forward to package-macos-app.sh
  --universal                     Forward to package-macos-app.sh. Default
  --native                        Forward to package-macos-app.sh
  --entitlements PATH             Forward to package-macos-app.sh
  --widget-entitlements PATH      Forward to package-macos-app.sh
  --include-local-test-pets       Forward to package-macos-app.sh
  --exclude-local-test-pets       Forward to package-macos-app.sh
  --help                          Show this help

Environment:
  FOCUSPET_CODESIGN_IDENTITY      Developer ID Application identity
  FOCUSPET_NOTARY_PROFILE         Preferred notarytool keychain profile
  FOCUSPET_NOTARY_APPLE_ID        Alternative notary Apple ID
  FOCUSPET_NOTARY_TEAM_ID         Alternative notary team ID
  FOCUSPET_NOTARY_PASSWORD        Alternative app-specific password

One-time notary profile setup:
  xcrun notarytool store-credentials focuspet-notary \
    --apple-id you@example.com --team-id TEAMID --password app-specific-password
USAGE
}

die() {
    echo "error: $*" >&2
    exit 64
}

notary_args_available() {
    [[ -n "$NOTARY_PROFILE" ]] || {
        [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_PASSWORD" ]]
    }
}

require_developer_id_identity() {
    local identity_line
    identity_line="$(security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" | head -n 1 || true)"

    if [[ -z "$identity_line" ]]; then
        die "signing identity was not found in the keychain: $SIGN_IDENTITY"
    fi

    if [[ "$identity_line" != *"Developer ID Application:"* ]]; then
        die "distribution DMGs require a Developer ID Application certificate, but matched: $identity_line"
    fi
}

require_distribution_config() {
    if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
        die "distribution DMGs require FOCUSPET_CODESIGN_IDENTITY or --sign-identity with a Developer ID Application certificate"
    fi

    require_developer_id_identity

    if ! notary_args_available; then
        die "distribution DMGs require FOCUSPET_NOTARY_PROFILE or Apple ID/team/password notary credentials"
    fi
}

submit_for_notarization() {
    local artifact="$1"
    local label="$2"

    echo "Submitting $label for notarization..."
    if [[ -n "$NOTARY_PROFILE" ]]; then
        xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$artifact" \
            --apple-id "$NOTARY_APPLE_ID" \
            --team-id "$NOTARY_TEAM_ID" \
            --password "$NOTARY_PASSWORD" \
            --wait
    fi
}

staple_and_validate() {
    local artifact="$1"
    local label="$2"

    echo "Stapling $label..."
    xcrun stapler staple "$artifact"
    xcrun stapler validate "$artifact"
}

verify_app_signature() {
    local app_path="$1"

    codesign --verify --deep --strict --verbose=2 "$app_path"
    if [[ "$MODE" == "distribution" ]]; then
        spctl -a -vv --type execute "$app_path"
    fi
}

verify_dmg_signature() {
    local dmg_path="$1"

    hdiutil verify "$dmg_path" >/dev/null
    if [[ "$MODE" == "distribution" ]]; then
        codesign --verify --verbose=2 "$dmg_path"
        xcrun stapler validate "$dmg_path"
        spctl -a -t open --context context:primary-signature -vv "$dmg_path"
    fi
}

verify_dmg_background_asset() {
    local image_path="$1"
    local image_size

    test -f "$image_path" || die "DMG background asset is missing: $image_path"
    image_size="$(sips -g pixelWidth -g pixelHeight "$image_path" 2>/dev/null | awk '/pixelWidth/ { width = $2 } /pixelHeight/ { height = $2 } END { print width "x" height }')"
    [[ "$image_size" == "1440x920" ]] || die "DMG background asset must be 1440x920 Retina PNG for a ${WINDOW_WIDTH}x${WINDOW_HEIGHT} Finder window, got $image_size: $image_path"
}

write_release_manifest() {
    local dmg_path="$1"
    local latest_path="$2"
    local app_path="$3"
    local sha_path="$dmg_path.sha256"
    local manifest_path="$dmg_path.manifest.txt"
    local bundle_id
    local short_version
    local build_number
    local dmg_sha

    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
    short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
    build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
    dmg_sha="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"

    printf '%s  %s\n' "$dmg_sha" "$(basename "$dmg_path")" > "$sha_path"
    {
        echo "Focus Pet DMG Manifest"
        echo "Generated-UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Mode: $MODE"
        echo "Bundle-ID: $bundle_id"
        echo "Version: $short_version"
        echo "Build: $build_number"
        echo "DMG: $dmg_path"
        echo "Latest-DMG: $latest_path"
        echo "SHA256: $dmg_sha"
        echo
        echo "App codesign:"
        codesign --display --verbose=4 "$app_path" 2>&1 | sed 's/^/  /'
        if [[ "$MODE" == "distribution" ]]; then
            echo
            echo "DMG codesign:"
            codesign --display --verbose=4 "$dmg_path" 2>&1 | sed 's/^/  /'
            echo
            echo "Stapler DMG validation:"
            xcrun stapler validate "$dmg_path" 2>&1 | sed 's/^/  /'
        fi
    } > "$manifest_path"
}

verify_local_test_pets() {
    local app_path="$1"
    local packs_dir="$app_path/Contents/Resources/LocalPetPacks"
    local pack_count
    local pack_dir
    local unexpected_pack

    test -d "$packs_dir" || die "LocalPetPacks directory is missing: $packs_dir"
    pack_count="$(find "$packs_dir" -mindepth 2 -maxdepth 2 -name pet.json -print | wc -l | tr -d '[:space:]')"
    [[ "$pack_count" -eq "${#EXPECTED_LOCAL_PET_PACK_DIRS[@]}" ]] || die "LocalPetPacks contains $pack_count pet pack(s), expected ${#EXPECTED_LOCAL_PET_PACK_DIRS[@]}: $packs_dir"

    for pack_dir in "${EXPECTED_LOCAL_PET_PACK_DIRS[@]}"; do
        test -f "$packs_dir/$pack_dir/pet.json" || die "Expected local pet pack is missing: $packs_dir/$pack_dir"
    done

    unexpected_pack="$(
        find "$packs_dir" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r candidate; do
            local name
            name="$(basename "$candidate")"
            local expected=0
            for pack_dir in "${EXPECTED_LOCAL_PET_PACK_DIRS[@]}"; do
                [[ "$name" == "$pack_dir" ]] && expected=1
            done
            [[ "$expected" -eq 1 ]] || printf '%s\n' "$name"
        done | head -n 1
    )"
    [[ -z "$unexpected_pack" ]] || die "Unexpected local pet pack is bundled: $unexpected_pack"
    echo "Included expected local pet packs: ${EXPECTED_LOCAL_PET_PACK_DIRS[*]}."
}

verify_no_local_test_pets() {
    local app_path="$1"
    local packs_dir="$app_path/Contents/Resources/LocalPetPacks"

    if [[ -e "$packs_dir" ]]; then
        die "LocalPetPacks is present in a build that should exclude local-only pet assets: $packs_dir"
    fi
}

verify_widget_extension() {
    local app_path="$1"
    local verify_args=(--no-register)

    if [[ "$MODE" == "distribution" ]]; then
        verify_args+=(--require-gallery-ready)
    fi

    "$WIDGET_VERIFY_SCRIPT" "${verify_args[@]}" "$app_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            MODE="local"
            shift
            ;;
        --distribution)
            MODE="distribution"
            shift
            ;;
        --skip-verify)
            VERIFY=0
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:-}"
            shift 2
            ;;
        --apple-id)
            NOTARY_APPLE_ID="${2:-}"
            shift 2
            ;;
        --team-id)
            NOTARY_TEAM_ID="${2:-}"
            shift 2
            ;;
        --password)
            NOTARY_PASSWORD="${2:-}"
            shift 2
            ;;
        --bundle-identifier|--widget-bundle-identifier|--version|--build|--entitlements|--widget-entitlements)
            APP_ARGS+=("$1" "${2:-}")
            shift 2
            ;;
        --include-local-test-pets)
            APP_ARGS+=("$1")
            PET_PACK_MODE_SET=1
            INCLUDE_LOCAL_TEST_PETS_EFFECTIVE=1
            shift
            ;;
        --exclude-local-test-pets)
            APP_ARGS+=("$1")
            PET_PACK_MODE_SET=1
            INCLUDE_LOCAL_TEST_PETS_EFFECTIVE=0
            shift
            ;;
        --universal|--native)
            APP_ARGS+=("$1")
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

case "$MODE" in
    distribution)
        require_distribution_config
        APP_ARGS+=(--sign-identity "$SIGN_IDENTITY")
        if [[ "$PET_PACK_MODE_SET" -eq 0 ]]; then
            APP_ARGS+=(--exclude-local-test-pets)
            INCLUDE_LOCAL_TEST_PETS_EFFECTIVE=0
        fi
        DIST_OUTPUT_DIR="$DIST_DIR"
        LATEST_DMG="$DIST_DIR/FocusPet.dmg"
        ;;
    local)
        if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
            APP_ARGS+=(--sign-identity "$SIGN_IDENTITY")
        else
            APP_ARGS+=(--ad-hoc-sign)
        fi
        if [[ "$PET_PACK_MODE_SET" -eq 0 ]]; then
            APP_ARGS+=(--exclude-local-test-pets)
            INCLUDE_LOCAL_TEST_PETS_EFFECTIVE=0
        fi
        DIST_OUTPUT_DIR="$LOCAL_DIST_DIR"
        LATEST_DMG="$LOCAL_DIST_DIR/FocusPet-local.dmg"
        ;;
    *)
        die "invalid mode: $MODE"
        ;;
esac

mkdir -p "$DIST_OUTPUT_DIR" "$WORK_DIR"
APP_PATH="$("$APP_SCRIPT" "${APP_ARGS[@]}" | tail -n 1)"
APP_BUNDLE_NAME="$(basename "$APP_PATH")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

if [[ "$MODE" == "distribution" ]]; then
    DMG_BASENAME="FocusPet-${VERSION}-${BUILD}"
else
    DMG_BASENAME="FocusPet-local-${VERSION}-${BUILD}"
fi

APP_ZIP="$WORK_DIR/$DMG_BASENAME.app.zip"
RW_DMG="$WORK_DIR/$DMG_BASENAME.rw.dmg"
FINAL_DMG="$DIST_OUTPUT_DIR/$DMG_BASENAME.dmg"
MOUNT_POINT="$WORK_DIR/mount"
VERIFY_MOUNT_POINT="$WORK_DIR/verify-mount"

cleanup() {
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    hdiutil detach "$VERIFY_MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" >/dev/null 2>&1 \
        || hdiutil detach -force "/Volumes/$VOLUME_NAME" >/dev/null 2>&1 \
        || true
fi

rm -rf "$STAGING_DIR" "$MOUNT_POINT" "$VERIFY_MOUNT_POINT" "$APP_ZIP" "$RW_DMG" "$FINAL_DMG" "$LATEST_DMG"
mkdir -p "$STAGING_DIR/.background" "$MOUNT_POINT" "$VERIFY_MOUNT_POINT"
verify_dmg_background_asset "$DMG_BACKGROUND_ASSET"

verify_app_signature "$APP_PATH"
verify_widget_extension "$APP_PATH"
if [[ "$INCLUDE_LOCAL_TEST_PETS_EFFECTIVE" -eq 1 ]]; then
    verify_local_test_pets "$APP_PATH"
else
    verify_no_local_test_pets "$APP_PATH"
fi

if [[ "$MODE" == "distribution" ]]; then
    echo "Creating app notarization archive..."
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    submit_for_notarization "$APP_ZIP" "$APP_BUNDLE_NAME"
    staple_and_validate "$APP_PATH" "$APP_BUNDLE_NAME"
    verify_app_signature "$APP_PATH"
fi

ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
ditto "$DMG_BACKGROUND_ASSET" "$BACKGROUND_PNG"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" >/dev/null

osascript <<OSA
tell application "Finder"
    activate
    set dmgFolder to (POSIX file "$MOUNT_POINT") as alias
    try
        close (every Finder window whose name is "$VOLUME_NAME")
    end try
    open dmgFolder
    repeat with windowAttempt from 1 to 10
        delay 0.3
        try
            set dmgWindow to container window of dmgFolder
            exit repeat
        end try
        if windowAttempt is 10 then error "DMG Finder window did not open"
    end repeat
    set dmgWindowID to id of dmgWindow
    set current view of dmgWindow to icon view
    try
        set toolbar visible of dmgWindow to false
    end try
    try
        set statusbar visible of dmgWindow to false
    end try
    set bounds of dmgWindow to {160, 120, 160 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}
    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 14
    set background picture of viewOptions to ((POSIX file "$MOUNT_POINT/.background/background.png") as alias)
    set position of item "$APP_BUNDLE_NAME" of dmgFolder to {210, 230}
    set position of item "Applications" of dmgFolder to {510, 230}
    update dmgFolder without registering applications
    try
        set toolbar visible of dmgWindow to false
    end try
    try
        set statusbar visible of dmgWindow to false
    end try
    delay 1
    if position of item "$APP_BUNDLE_NAME" of dmgFolder is not {210, 230} then error "DMG app icon position was not persisted"
    if position of item "Applications" of dmgFolder is not {510, 230} then error "DMG Applications icon position was not persisted"
    close Finder window id dmgWindowID
    delay 3
    open dmgFolder
    repeat with verifyAttempt from 1 to 10
        delay 0.3
        try
            set verifyWindow to container window of dmgFolder
            exit repeat
        end try
        if verifyAttempt is 10 then error "DMG Finder verify window did not open"
    end repeat
    set verifyOptions to icon view options of verifyWindow
    if current view of verifyWindow is not icon view then error "DMG icon view was not persisted"
    if icon size of verifyOptions is not 96 then error "DMG icon size was not persisted"
    if text size of verifyOptions is not 14 then error "DMG text size was not persisted"
    close verifyWindow
end tell
OSA

sync
sleep 3
hdiutil detach "$MOUNT_POINT" >/dev/null

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

if [[ "$MODE" == "distribution" ]]; then
    echo "Signing distribution DMG..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
    submit_for_notarization "$FINAL_DMG" "$(basename "$FINAL_DMG")"
    staple_and_validate "$FINAL_DMG" "$(basename "$FINAL_DMG")"
fi

cp "$FINAL_DMG" "$LATEST_DMG"
write_release_manifest "$FINAL_DMG" "$LATEST_DMG" "$APP_PATH"

if [[ "$VERIFY" -eq 1 ]]; then
    verify_dmg_signature "$FINAL_DMG"
    hdiutil attach -nobrowse -readonly "$FINAL_DMG" -mountpoint "$VERIFY_MOUNT_POINT" >/dev/null
    test -d "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME"
    test -L "$VERIFY_MOUNT_POINT/Applications"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME/Contents/Info.plist" >/dev/null
    verify_app_signature "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME"
    verify_widget_extension "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME"
    if [[ "$INCLUDE_LOCAL_TEST_PETS_EFFECTIVE" -eq 1 ]]; then
        verify_local_test_pets "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME"
    else
        verify_no_local_test_pets "$VERIFY_MOUNT_POINT/$APP_BUNDLE_NAME"
    fi
    hdiutil detach "$VERIFY_MOUNT_POINT" >/dev/null
fi

echo "$FINAL_DMG"
echo "$LATEST_DMG"
