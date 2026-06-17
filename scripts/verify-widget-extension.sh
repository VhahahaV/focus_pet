#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/Focus Pet.app"
REGISTER=1
REQUIRE_GALLERY_READY=0

usage() {
    cat <<'USAGE'
Usage: scripts/verify-widget-extension.sh [options] [Focus Pet.app]

Validates that a packaged Focus Pet app embeds a WidgetKit extension and can be
registered through PlugInKit. PlugInKit registration only proves bundle
discovery; macOS WidgetKit gallery visibility also requires the containing app
and extension to be trusted by the system widget service.

Options:
  --register                Register the widget extension with PlugInKit. Default
  --no-register             Only inspect bundle structure and signing
  --require-gallery-ready   Fail ad-hoc or unsigned builds that chronod can skip
  --help                    Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --register)
            REGISTER=1
            shift
            ;;
        --no-register)
            REGISTER=0
            shift
            ;;
        --require-gallery-ready)
            REQUIRE_GALLERY_READY=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
        *)
            APP_PATH="$1"
            shift
            ;;
    esac
done

EXTENSION_DIR="$APP_PATH/Contents/PlugIns/FocusPetWidgetExtension.appex"
APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
INFO_PLIST="$EXTENSION_DIR/Contents/Info.plist"
EXECUTABLE="$EXTENSION_DIR/Contents/MacOS/FocusPetWidgetExtension"

die() {
    echo "error: $*" >&2
    exit 1
}

test -d "$APP_PATH" || die "app bundle does not exist: $APP_PATH"
test -f "$APP_INFO_PLIST" || die "app Info.plist is missing: $APP_INFO_PLIST"
test -d "$EXTENSION_DIR" || die "widget extension is missing: $EXTENSION_DIR"
test -f "$INFO_PLIST" || die "widget extension Info.plist is missing: $INFO_PLIST"
test -x "$EXECUTABLE" || die "widget extension executable is missing: $EXECUTABLE"

APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
PACKAGE_TYPE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO_PLIST")"
EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$INFO_PLIST")"

[[ "$PACKAGE_TYPE" == "XPC!" ]] || die "unexpected widget package type: $PACKAGE_TYPE"
[[ "$EXTENSION_POINT" == "com.apple.widgetkit-extension" ]] || die "unexpected extension point: $EXTENSION_POINT"

codesign --verify --strict --verbose=2 "$EXTENSION_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

signature_field() {
    local details="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key {print $2; exit}' <<<"$details"
}

APP_SIGNATURE_DETAILS="$(codesign --display --verbose=4 "$APP_PATH" 2>&1)"
EXTENSION_SIGNATURE_DETAILS="$(codesign --display --verbose=4 "$EXTENSION_DIR" 2>&1)"
APP_SIGNATURE="$(signature_field "$APP_SIGNATURE_DETAILS" "Signature")"
EXTENSION_SIGNATURE="$(signature_field "$EXTENSION_SIGNATURE_DETAILS" "Signature")"
APP_TEAM_IDENTIFIER="$(signature_field "$APP_SIGNATURE_DETAILS" "TeamIdentifier")"
EXTENSION_TEAM_IDENTIFIER="$(signature_field "$EXTENSION_SIGNATURE_DETAILS" "TeamIdentifier")"

GALLERY_READY=1
GALLERY_WARNINGS=()
if [[ "$APP_SIGNATURE" == "adhoc" || "$EXTENSION_SIGNATURE" == "adhoc" ]]; then
    GALLERY_READY=0
    GALLERY_WARNINGS+=("ad-hoc signatures are accepted by codesign but can be rejected by chronod")
fi
if [[ "$APP_TEAM_IDENTIFIER" == "not set" || "$EXTENSION_TEAM_IDENTIFIER" == "not set" ]]; then
    GALLERY_READY=0
    GALLERY_WARNINGS+=("the app or extension has no TeamIdentifier")
fi

if [[ "$GALLERY_READY" -eq 0 ]]; then
    {
        echo "warning: native widget gallery readiness was not proven for $APP_BUNDLE_ID / $BUNDLE_ID"
        for warning in "${GALLERY_WARNINGS[@]}"; do
            echo "warning: $warning"
        done
        echo "warning: on macOS this can appear as: chronod Ignoring restricted or unknown extension $APP_BUNDLE_ID"
    } >&2
    if [[ "$REQUIRE_GALLERY_READY" -eq 1 ]]; then
        die "gallery-ready validation requires a trusted Apple Development or Developer ID signed app and widget extension"
    fi
fi

if [[ "$REGISTER" -eq 1 ]]; then
    pluginkit -a "$EXTENSION_DIR"
    PLUGINKIT_MATCHES="$(pluginkit -m -v -p com.apple.widgetkit-extension -i "$BUNDLE_ID")"
    if [[ "$PLUGINKIT_MATCHES" != *"$EXTENSION_DIR"* ]]; then
        echo "$PLUGINKIT_MATCHES"
        die "PlugInKit did not register $BUNDLE_ID at $EXTENSION_DIR"
    fi
    echo "$PLUGINKIT_MATCHES"
else
    echo "Validated $BUNDLE_ID without registering it."
fi

if [[ "$GALLERY_READY" -eq 1 ]]; then
    echo "Gallery readiness checks passed for $APP_BUNDLE_ID / $BUNDLE_ID."
else
    echo "Bundle and PlugInKit checks passed; gallery visibility still requires trusted signing."
fi
