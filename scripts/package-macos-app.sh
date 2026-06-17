#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_NAME="Focus Pet.app"
APP_DIR="$ROOT_DIR/.build/$APP_BUNDLE_NAME"
LEGACY_APP_DIR="$ROOT_DIR/.build/FocusPet.app"
LOCAL_PET_PACKS_ROOT="$ROOT_DIR/external_generated_packs"
APP_ICON="$ROOT_DIR/Sources/FocusPetMac/Resources/AppIcon.icns"
EXPECTED_LOCAL_PET_PACK_DIRS=(
    "LuoXiaoHeiLocal"
    "PixelCatMemeLocal"
    "XiaoDaiLocal"
)

CONFIGURATION="${FOCUSPET_BUILD_CONFIGURATION:-release}"
BUNDLE_IDENTIFIER="${FOCUSPET_BUNDLE_IDENTIFIER:-com.focuspet.FocusPet}"
WIDGET_EXTENSION_PRODUCT_NAME="FocusPetWidgetExtension"
WIDGET_EXTENSION_BUNDLE_NAME="$WIDGET_EXTENSION_PRODUCT_NAME.appex"
WIDGET_EXTENSION_BUNDLE_IDENTIFIER="${FOCUSPET_WIDGET_BUNDLE_IDENTIFIER:-}"
VERSION="${FOCUSPET_VERSION:-0.0.1}"
BUILD_NUMBER="${FOCUSPET_BUILD_NUMBER:-1}"
INCLUDE_LOCAL_TEST_PETS=0
SIGN_MODE="auto"
SIGN_IDENTITY="${FOCUSPET_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
ENTITLEMENTS="${FOCUSPET_ENTITLEMENTS:-}"
WIDGET_EXTENSION_ENTITLEMENTS="${FOCUSPET_WIDGET_ENTITLEMENTS:-}"
HARDENED_RUNTIME=1
ARCH_MODE="${FOCUSPET_ARCH_MODE:-universal}"

usage() {
    cat <<'USAGE'
Usage: scripts/package-macos-app.sh [options]

Options:
  --configuration debug|release     Swift build configuration. Default: release
  --bundle-identifier ID            CFBundleIdentifier. Default: com.focuspet.FocusPet
  --widget-bundle-identifier ID     Widget extension identifier. Default: <bundle-id>.WidgetExtension
  --version VERSION                 CFBundleShortVersionString. Default: 0.0.1
  --build BUILD                     CFBundleVersion. Default: 1
  --universal                       Build arm64+x86_64 app executable. Default
  --native                          Build only the current machine architecture
  --include-local-test-pets         Include external_generated_packs for local testing only
  --exclude-local-test-pets         Exclude external_generated_packs. Default
  --sign-identity IDENTITY          Sign with a Developer ID/Application identity
  --ad-hoc-sign                     Sign ad-hoc for local-only testing
  --skip-sign                       Leave the bundle unsigned
  --entitlements PATH               Pass an entitlements plist to codesign
  --widget-entitlements PATH        Pass widget extension entitlements to codesign
  --no-hardened-runtime             Do not pass --options runtime to codesign
  --help                            Show this help

Environment:
  FOCUSPET_CODESIGN_IDENTITY        Default signing identity
  FOCUSPET_BUNDLE_IDENTIFIER        Default bundle identifier
  FOCUSPET_WIDGET_BUNDLE_IDENTIFIER Default widget extension bundle identifier
  FOCUSPET_VERSION                  Default short version
  FOCUSPET_BUILD_NUMBER             Default build number
  FOCUSPET_ENTITLEMENTS             Default entitlements plist path
  FOCUSPET_WIDGET_ENTITLEMENTS      Default widget extension entitlements plist path
  FOCUSPET_ARCH_MODE                universal or native. Default: universal
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
        --widget-bundle-identifier)
            WIDGET_EXTENSION_BUNDLE_IDENTIFIER="${2:-}"
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
        --universal)
            ARCH_MODE="universal"
            shift
            ;;
        --native)
            ARCH_MODE="native"
            shift
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
        --widget-entitlements)
            WIDGET_EXTENSION_ENTITLEMENTS="${2:-}"
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
if [[ -z "$WIDGET_EXTENSION_BUNDLE_IDENTIFIER" ]]; then
    WIDGET_EXTENSION_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER.WidgetExtension"
fi
if [[ -z "$WIDGET_EXTENSION_BUNDLE_IDENTIFIER" ]]; then
    echo "Widget extension bundle identifier must be non-empty." >&2
    exit 64
fi

case "$ARCH_MODE" in
    universal|native)
        ;;
    *)
        echo "Invalid architecture mode: $ARCH_MODE" >&2
        exit 64
        ;;
esac

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
if [[ -n "$WIDGET_EXTENSION_ENTITLEMENTS" && ! -f "$WIDGET_EXTENSION_ENTITLEMENTS" ]]; then
    echo "Widget extension entitlements file does not exist: $WIDGET_EXTENSION_ENTITLEMENTS" >&2
    exit 66
fi

copy_expected_local_pet_packs() {
    local destination_root="$1"
    mkdir -p "$destination_root"

    for pack_dir in "${EXPECTED_LOCAL_PET_PACK_DIRS[@]}"; do
        local source_dir="$LOCAL_PET_PACKS_ROOT/$pack_dir"
        if [[ ! -f "$source_dir/pet.json" ]]; then
            echo "Expected local pet pack is missing pet.json: $source_dir" >&2
            exit 66
        fi
        cp -R "$source_dir" "$destination_root/$pack_dir"
    done
}

cd "$ROOT_DIR"

if [[ "$ARCH_MODE" == "universal" ]]; then
    ARM_TRIPLE="arm64-apple-macosx14.0"
    X86_TRIPLE="x86_64-apple-macosx14.0"
    swift build --configuration "$CONFIGURATION" --triple "$ARM_TRIPLE" --product FocusPet
    swift build --configuration "$CONFIGURATION" --triple "$ARM_TRIPLE" --product "$WIDGET_EXTENSION_PRODUCT_NAME"
    swift build --configuration "$CONFIGURATION" --triple "$X86_TRIPLE" --product FocusPet
    swift build --configuration "$CONFIGURATION" --triple "$X86_TRIPLE" --product "$WIDGET_EXTENSION_PRODUCT_NAME"

    ARM_BUILD_PRODUCTS_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION"
    X86_BUILD_PRODUCTS_DIR="$ROOT_DIR/.build/x86_64-apple-macosx/$CONFIGURATION"
    BUILD_PRODUCTS_DIR="$ARM_BUILD_PRODUCTS_DIR"
    ARM_EXECUTABLE="$ARM_BUILD_PRODUCTS_DIR/FocusPet"
    X86_EXECUTABLE="$X86_BUILD_PRODUCTS_DIR/FocusPet"
    ARM_WIDGET_EXTENSION_EXECUTABLE="$ARM_BUILD_PRODUCTS_DIR/$WIDGET_EXTENSION_PRODUCT_NAME"
    X86_WIDGET_EXTENSION_EXECUTABLE="$X86_BUILD_PRODUCTS_DIR/$WIDGET_EXTENSION_PRODUCT_NAME"

    if [[ ! -x "$ARM_EXECUTABLE" ]]; then
        echo "Built arm64 executable is missing: $ARM_EXECUTABLE" >&2
        exit 70
    fi
    if [[ ! -x "$X86_EXECUTABLE" ]]; then
        echo "Built x86_64 executable is missing: $X86_EXECUTABLE" >&2
        exit 70
    fi
    if [[ ! -x "$ARM_WIDGET_EXTENSION_EXECUTABLE" ]]; then
        echo "Built arm64 widget extension executable is missing: $ARM_WIDGET_EXTENSION_EXECUTABLE" >&2
        exit 70
    fi
    if [[ ! -x "$X86_WIDGET_EXTENSION_EXECUTABLE" ]]; then
        echo "Built x86_64 widget extension executable is missing: $X86_WIDGET_EXTENSION_EXECUTABLE" >&2
        exit 70
    fi
else
    swift build --configuration "$CONFIGURATION" --product FocusPet
    swift build --configuration "$CONFIGURATION" --product "$WIDGET_EXTENSION_PRODUCT_NAME"
    BUILD_PRODUCTS_DIR="$ROOT_DIR/.build/$CONFIGURATION"
    EXECUTABLE="$BUILD_PRODUCTS_DIR/FocusPet"
    WIDGET_EXTENSION_EXECUTABLE="$BUILD_PRODUCTS_DIR/$WIDGET_EXTENSION_PRODUCT_NAME"

    if [[ ! -x "$EXECUTABLE" ]]; then
        echo "Built executable is missing: $EXECUTABLE" >&2
        exit 70
    fi
    if [[ ! -x "$WIDGET_EXTENSION_EXECUTABLE" ]]; then
        echo "Built widget extension executable is missing: $WIDGET_EXTENSION_EXECUTABLE" >&2
        exit 70
    fi
fi

rm -rf "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"
WIDGET_EXTENSION_DIR="$APP_DIR/Contents/PlugIns/$WIDGET_EXTENSION_BUNDLE_NAME"
mkdir -p \
    "$APP_DIR/Contents/MacOS" \
    "$APP_DIR/Contents/Resources" \
    "$WIDGET_EXTENSION_DIR/Contents/MacOS" \
    "$WIDGET_EXTENSION_DIR/Contents/Resources"
if [[ "$ARCH_MODE" == "universal" ]]; then
    lipo -create "$ARM_EXECUTABLE" "$X86_EXECUTABLE" -output "$APP_DIR/Contents/MacOS/FocusPet"
    lipo "$APP_DIR/Contents/MacOS/FocusPet" -verify_arch arm64 x86_64
    lipo -create "$ARM_WIDGET_EXTENSION_EXECUTABLE" "$X86_WIDGET_EXTENSION_EXECUTABLE" -output "$WIDGET_EXTENSION_DIR/Contents/MacOS/$WIDGET_EXTENSION_PRODUCT_NAME"
    lipo "$WIDGET_EXTENSION_DIR/Contents/MacOS/$WIDGET_EXTENSION_PRODUCT_NAME" -verify_arch arm64 x86_64
else
    cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FocusPet"
    cp "$WIDGET_EXTENSION_EXECUTABLE" "$WIDGET_EXTENSION_DIR/Contents/MacOS/$WIDGET_EXTENSION_PRODUCT_NAME"
fi
chmod +x "$WIDGET_EXTENSION_DIR/Contents/MacOS/$WIDGET_EXTENSION_PRODUCT_NAME"

for RESOURCE_BUNDLE in "$BUILD_PRODUCTS_DIR"/FocusPet_*.bundle; do
    [[ -d "$RESOURCE_BUNDLE" ]] || continue
    BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
    cp -R "$RESOURCE_BUNDLE" "$WIDGET_EXTENSION_DIR/Contents/Resources/"
done

if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ "$INCLUDE_LOCAL_TEST_PETS" -eq 1 && -d "$LOCAL_PET_PACKS_ROOT" ]]; then
    copy_expected_local_pet_packs "$APP_DIR/Contents/Resources/LocalPetPacks"
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

cat > "$WIDGET_EXTENSION_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Focus Pet</string>
    <key>CFBundleExecutable</key>
    <string>$WIDGET_EXTENSION_PRODUCT_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$WIDGET_EXTENSION_BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Focus Pet Widget Extension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

plutil -lint "$WIDGET_EXTENSION_DIR/Contents/Info.plist" >/dev/null

if [[ "$SIGN_MODE" != "none" ]]; then
    BASE_CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        BASE_CODESIGN_ARGS+=(--timestamp)
    fi
    if [[ "$HARDENED_RUNTIME" -eq 1 ]]; then
        BASE_CODESIGN_ARGS+=(--options runtime)
    fi

    EFFECTIVE_WIDGET_EXTENSION_ENTITLEMENTS="$WIDGET_EXTENSION_ENTITLEMENTS"
    if [[ -z "$EFFECTIVE_WIDGET_EXTENSION_ENTITLEMENTS" ]]; then
        EFFECTIVE_WIDGET_EXTENSION_ENTITLEMENTS="$ROOT_DIR/.build/focuspet-widget-extension.entitlements"
        cat > "$EFFECTIVE_WIDGET_EXTENSION_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array>
        <string>/Library/Application Support/Focus Pet/</string>
    </array>
</dict>
</plist>
PLIST
    fi

    WIDGET_CODESIGN_ARGS=("${BASE_CODESIGN_ARGS[@]}" --entitlements "$EFFECTIVE_WIDGET_EXTENSION_ENTITLEMENTS")
    APP_CODESIGN_ARGS=("${BASE_CODESIGN_ARGS[@]}")
    if [[ -n "$ENTITLEMENTS" ]]; then
        APP_CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
    fi

    echo "Signing $WIDGET_EXTENSION_BUNDLE_NAME with ${SIGN_IDENTITY}..."
    codesign "${WIDGET_CODESIGN_ARGS[@]}" "$WIDGET_EXTENSION_DIR"
    codesign --verify --strict --verbose=2 "$WIDGET_EXTENSION_DIR"

    echo "Signing $APP_BUNDLE_NAME with ${SIGN_IDENTITY}..."
    codesign "${APP_CODESIGN_ARGS[@]}" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"

    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "Warning: ad-hoc signed WidgetKit extensions can pass bundle checks but may be hidden by the native macOS widget gallery." >&2
        echo "Warning: use --sign-identity with an Apple Development or Developer ID identity for gallery-ready validation." >&2
    fi
else
    echo "Warning: $APP_BUNDLE_NAME was not signed." >&2
fi

echo "$APP_DIR"
