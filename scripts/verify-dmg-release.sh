#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/dist/FocusPet.dmg"
APP_BUNDLE_NAME="Focus Pet.app"
MODE="distribution"
OPEN_SMOKE=0
INSTALL_TO=""
REPLACE_INSTALL=0
QUARANTINE=1
EXPECT_LOCAL_TEST_PETS=0
LAUNCHED_EXECUTABLE=""
REPORT_PATH=""

usage() {
    cat <<'USAGE'
Usage: scripts/verify-dmg-release.sh [options] [path/to/FocusPet.dmg]

Verifies a Focus Pet DMG as if it had been downloaded on another Mac. In
distribution mode it requires signing, notarization, staple tickets, Gatekeeper
acceptance, a valid mounted app, and a quarantined-copy mount check.

Options:
  --local                 Skip distribution-only gates for local smoke DMGs
  --distribution          Require distribution gates. Default
  --open-smoke            Launch the mounted or installed app and confirm it runs
  --expect-local-test-pets
                          Require bundled LocalPetPacks to contain pet manifests
  --install-to DIR        Copy the app into DIR and verify the copied app
  --replace               Replace an existing app at --install-to
  --no-quarantine         Local mode only: skip downloaded-file simulation
  --report PATH           Write verification evidence to PATH
  --app-name NAME.app     Expected app bundle name. Default: Focus Pet.app
  --help                  Show this help

Examples:
  scripts/verify-dmg-release.sh dist/FocusPet.dmg
  scripts/verify-dmg-release.sh --local dist/local/FocusPet-local.dmg
  scripts/verify-dmg-release.sh --local --no-quarantine --open-smoke dist/local/FocusPet-local.dmg
  scripts/verify-dmg-release.sh --install-to /Applications --replace dist/FocusPet.dmg
USAGE
}

die() {
    echo "error: $*" >&2
    exit 1
}

verify_distribution_dmg() {
    local dmg_path="$1"

    echo "Verifying distribution DMG signature, staple, and Gatekeeper status..."
    codesign --verify --verbose=2 "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl -a -t open --context context:primary-signature -vv "$dmg_path"
}

verify_app() {
    local app_path="$1"

    echo "Verifying app bundle: $app_path"
    test -d "$app_path" || die "app bundle is missing: $app_path"
    codesign --verify --deep --strict --verbose=2 "$app_path"

    if [[ "$MODE" == "distribution" ]]; then
        xcrun stapler validate "$app_path"
        spctl -a -vv --type execute "$app_path"
    fi
}

verify_local_test_pets() {
    local app_path="$1"
    local packs_dir="$app_path/Contents/Resources/LocalPetPacks"
    local pack_count

    test -d "$packs_dir" || die "LocalPetPacks directory is missing: $packs_dir"
    pack_count="$(find "$packs_dir" -mindepth 2 -maxdepth 2 -name pet.json -print | wc -l | tr -d '[:space:]')"
    [[ "$pack_count" -gt 0 ]] || die "LocalPetPacks does not contain any pet.json manifests: $packs_dir"
    echo "Found $pack_count packaged local pet pack(s)."
}

verify_install_link() {
    local mount_point="$1"
    local link_path="$mount_point/Applications"

    test -L "$link_path" || die "Applications symlink is missing in mounted DMG"
    local target
    target="$(readlink "$link_path")"
    [[ "$target" == "/Applications" ]] || die "Applications symlink points to $target instead of /Applications"
}

open_smoke() {
    local app_path="$1"
    local executable="$app_path/Contents/MacOS/FocusPet"
    local canonical_executable

    test -x "$executable" || die "app executable is missing: $executable"
    canonical_executable="$(realpath "$executable")"
    LAUNCHED_EXECUTABLE="$canonical_executable"

    echo "Launching smoke test..."
    open -n -a "$app_path"

    for _ in {1..10}; do
        if pgrep -f "$canonical_executable" >/dev/null || pgrep -f "$executable" >/dev/null; then
            pkill -f "$canonical_executable" >/dev/null 2>&1 || pkill -f "$executable" >/dev/null 2>&1 || true
            LAUNCHED_EXECUTABLE=""
            echo "Launch smoke test passed."
            return
        fi
        sleep 1
    done

    die "FocusPet did not stay running after launch"
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
        --open-smoke)
            OPEN_SMOKE=1
            shift
            ;;
        --expect-local-test-pets)
            EXPECT_LOCAL_TEST_PETS=1
            shift
            ;;
        --install-to)
            INSTALL_TO="${2:-}"
            shift 2
            ;;
        --replace)
            REPLACE_INSTALL=1
            shift
            ;;
        --no-quarantine)
            QUARANTINE=0
            shift
            ;;
        --report)
            REPORT_PATH="${2:-}"
            shift 2
            ;;
        --app-name)
            APP_BUNDLE_NAME="${2:-}"
            shift 2
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
            DMG_PATH="$1"
            shift
            ;;
    esac
done

case "$MODE" in
    distribution|local)
        ;;
    *)
        die "invalid mode: $MODE"
        ;;
esac

if [[ -z "$APP_BUNDLE_NAME" || "$APP_BUNDLE_NAME" != *.app ]]; then
    die "--app-name must be a non-empty .app bundle name"
fi

if [[ -z "$DMG_PATH" ]]; then
    die "DMG path is required"
fi

if [[ "$MODE" == "distribution" && "$QUARANTINE" -eq 0 ]]; then
    die "--no-quarantine is only allowed with --local; release verification must simulate a downloaded file"
fi

if [[ "$MODE" == "local" && "$OPEN_SMOKE" -eq 1 && "$QUARANTINE" -eq 1 ]]; then
    die "--open-smoke with --local requires --no-quarantine; quarantined local DMGs are expected to be blocked by Gatekeeper"
fi

if [[ "$DMG_PATH" != /* ]]; then
    DMG_PATH="$ROOT_DIR/$DMG_PATH"
fi

test -f "$DMG_PATH" || die "DMG does not exist: $DMG_PATH"

if [[ -z "$REPORT_PATH" ]]; then
    REPORT_PATH="$DMG_PATH.verification.txt"
elif [[ "$REPORT_PATH" != /* ]]; then
    REPORT_PATH="$ROOT_DIR/$REPORT_PATH"
fi

mkdir -p "$(dirname "$REPORT_PATH")"
exec > >(tee "$REPORT_PATH") 2>&1

echo "Focus Pet DMG Verification"
echo "Started-UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Mode: $MODE"
echo "DMG: $DMG_PATH"
echo "Report: $REPORT_PATH"
echo

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/focuspet-dmg-verify.XXXXXX")"
MOUNT_POINT="$TMP_DIR/mount"
DOWNLOADED_DMG="$TMP_DIR/downloaded-$(basename "$DMG_PATH")"
mkdir -p "$MOUNT_POINT"

cleanup() {
    if [[ -n "$LAUNCHED_EXECUTABLE" ]]; then
        pkill -f "$LAUNCHED_EXECUTABLE" >/dev/null 2>&1 || true
    fi
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || hdiutil detach -force "$MOUNT_POINT" >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Verifying image checksum..."
hdiutil verify "$DMG_PATH" >/dev/null

if [[ "$MODE" == "distribution" ]]; then
    verify_distribution_dmg "$DMG_PATH"
else
    echo "Local mode: skipping DMG Developer ID, staple, and Gatekeeper gates."
fi

if [[ "$QUARANTINE" -eq 1 ]]; then
    echo "Creating quarantined download simulation..."
else
    echo "Creating non-quarantined local smoke copy..."
fi
cp "$DMG_PATH" "$DOWNLOADED_DMG"
if [[ "$QUARANTINE" -eq 1 ]]; then
    xattr -w com.apple.quarantine "0083;$(printf "%x" "$(date +%s)");FocusPetVerifier;" "$DOWNLOADED_DMG"
fi

echo "Attaching DMG copy..."
hdiutil attach -nobrowse -readonly "$DOWNLOADED_DMG" -mountpoint "$MOUNT_POINT" >/dev/null

MOUNTED_APP="$MOUNT_POINT/$APP_BUNDLE_NAME"
verify_install_link "$MOUNT_POINT"
verify_app "$MOUNTED_APP"
if [[ "$EXPECT_LOCAL_TEST_PETS" -eq 1 ]]; then
    verify_local_test_pets "$MOUNTED_APP"
fi

LAUNCH_APP="$MOUNTED_APP"
if [[ -n "$INSTALL_TO" ]]; then
    [[ "$INSTALL_TO" == /* ]] || die "--install-to must be an absolute directory path"
    mkdir -p "$INSTALL_TO"
    INSTALLED_APP="$INSTALL_TO/$APP_BUNDLE_NAME"
    if [[ -e "$INSTALLED_APP" ]]; then
        [[ "$REPLACE_INSTALL" -eq 1 ]] || die "$INSTALLED_APP already exists; pass --replace to overwrite it"
        rm -rf "$INSTALLED_APP"
    fi

    echo "Installing app to $INSTALLED_APP..."
    ditto "$MOUNTED_APP" "$INSTALLED_APP"
    verify_app "$INSTALLED_APP"
    if [[ "$EXPECT_LOCAL_TEST_PETS" -eq 1 ]]; then
        verify_local_test_pets "$INSTALLED_APP"
    fi
    LAUNCH_APP="$INSTALLED_APP"
fi

if [[ "$OPEN_SMOKE" -eq 1 ]]; then
    open_smoke "$LAUNCH_APP"
fi

echo "DMG verification passed: $DMG_PATH"
echo "Finished-UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Verification report: $REPORT_PATH"
