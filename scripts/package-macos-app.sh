#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_NAME="Focus Pet.app"
APP_DIR="$ROOT_DIR/.build/$APP_BUNDLE_NAME"
LEGACY_APP_DIR="$ROOT_DIR/.build/FocusPet.app"
LOCAL_PET_PACKS_ROOT="$ROOT_DIR/external_generated_packs"
APP_ICON="$ROOT_DIR/Sources/FocusPetMac/Resources/AppIcon.icns"

CONFIGURATION="${FOCUSPET_BUILD_CONFIGURATION:-release}"
BUNDLE_IDENTIFIER="${FOCUSPET_BUNDLE_IDENTIFIER:-com.focuspet.FocusPet}"
VERSION="${FOCUSPET_VERSION:-0.0.1}"
BUILD_NUMBER="${FOCUSPET_BUILD_NUMBER:-1}"
INCLUDE_LOCAL_TEST_PETS=1
SIGN_MODE="auto"
SIGN_IDENTITY="${FOCUSPET_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
ENTITLEMENTS="${FOCUSPET_ENTITLEMENTS:-}"
HARDENED_RUNTIME=1

usage() {
    cat <<'USAGE'
Usage: scripts/package-macos-app.sh [options]

Options:
  --configuration debug|release     Swift build configuration. Default: release
  --bundle-identifier ID            CFBundleIdentifier. Default: com.focuspet.FocusPet
  --version VERSION                 CFBundleShortVersionString. Default: 0.0.1
  --build BUILD                     CFBundleVersion. Default: 1
  --include-local-test-pets         Include external_generated_packs. Default
  --exclude-local-test-pets         Exclude external_generated_packs
  --sign-identity IDENTITY          Sign with a Developer ID/Application identity
  --ad-hoc-sign                     Sign ad-hoc for local-only testing
  --skip-sign                       Leave the bundle unsigned
  --entitlements PATH               Pass an entitlements plist to codesign
  --no-hardened-runtime             Do not pass --options runtime to codesign
  --help                            Show this help

Environment:
  FOCUSPET_CODESIGN_IDENTITY        Default signing identity
  FOCUSPET_BUNDLE_IDENTIFIER        Default bundle identifier
  FOCUSPET_VERSION                  Default short version
  FOCUSPET_BUILD_NUMBER             Default build number
  FOCUSPET_ENTITLEMENTS             Default entitlements plist path
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --bundle-identifier)
            BUNDLE_IDENTIFIER="${2:-}"
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="${2:-}"
            shift 2
            ;;
        --include-local-test-pets)
            INCLUDE_LOCAL_TEST_PETS=1
            shift
            ;;
        --exclude-local-test-pets)
            INCLUDE_LOCAL_TEST_PETS=0
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            SIGN_MODE="identity"
            shift 2
            ;;
        --ad-hoc-sign)
            SIGN_IDENTITY="-"
            SIGN_MODE="ad-hoc"
            shift
            ;;
        --skip-sign)
            SIGN_IDENTITY=""
            SIGN_MODE="none"
            shift
            ;;
        --entitlements)
            ENTITLEMENTS="${2:-}"
            shift 2
            ;;
        --no-hardened-runtime)
            HARDENED_RUNTIME=0
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

case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "Invalid build configuration: $CONFIGURATION" >&2
        exit 64
        ;;
esac

if [[ -z "$BUNDLE_IDENTIFIER" || -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
    echo "Bundle identifier, version, and build number must be non-empty." >&2
    exit 64
fi

if [[ "$SIGN_MODE" == "auto" ]]; then
    if [[ -n "$SIGN_IDENTITY" ]]; then
        SIGN_MODE="identity"
    else
        SIGN_IDENTITY="-"
        SIGN_MODE="ad-hoc"
    fi
fi

if [[ -n "$ENTITLEMENTS" && ! -f "$ENTITLEMENTS" ]]; then
    echo "Entitlements file does not exist: $ENTITLEMENTS" >&2
    exit 66
fi

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION"

BUILD_PRODUCTS_DIR="$ROOT_DIR/.build/$CONFIGURATION"
EXECUTABLE="$BUILD_PRODUCTS_DIR/FocusPet"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Built executable is missing: $EXECUTABLE" >&2
    exit 70
fi

rm -rf "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FocusPet"

for RESOURCE_BUNDLE in "$BUILD_PRODUCTS_DIR"/FocusPet_*.bundle; do
    [[ -d "$RESOURCE_BUNDLE" ]] || continue
    BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
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

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Focus Pet</string>
    <key>CFBundleExecutable</key>
    <string>FocusPet</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Focus Pet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

if [[ "$SIGN_MODE" != "none" ]]; then
    CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        CODESIGN_ARGS+=(--timestamp)
    fi
    if [[ "$HARDENED_RUNTIME" -eq 1 ]]; then
        CODESIGN_ARGS+=(--options runtime)
    fi
    if [[ -n "$ENTITLEMENTS" ]]; then
        CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
    fi

    echo "Signing $APP_BUNDLE_NAME with ${SIGN_IDENTITY}..."
    codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
    echo "Warning: $APP_BUNDLE_NAME was not signed." >&2
fi

echo "$APP_DIR"
