#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="${FOCUSPET_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
ARCH_ARGS=(--universal)
OPEN_SMOKE=1
INSTALL_SMOKE_DIR="$ROOT_DIR/.build/dmg-open-smoke-install"

usage() {
    cat <<'USAGE'
Usage: scripts/build-verified-local-dmg.sh [options]

Builds a reproducible local-only Focus Pet DMG and verifies the full local
packaging chain:
  1. script syntax
  2. release Swift build
  3. local DMG packaging with no bundled pet packs
  4. DMG checksum
  5. mounted DMG layout and Finder installer window metadata
  6. downloaded-copy verifier confirming pet packs are excluded
  7. installed-copy launch smoke test

Options:
  --build BUILD       CFBundleVersion to pass through. Default: timestamp
  --native            Build only the current machine architecture
  --universal         Build arm64+x86_64. Default
  --skip-open-smoke   Skip installed-copy launch smoke test
  --help              Show this help

Output:
  dist/local/FocusPet-local-<version>-<build>.dmg
  dist/local/FocusPet-local.dmg
  *.verification.txt, *.finder-layout.txt, and optionally *.install-open-smoke.txt
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)
            BUILD_NUMBER="${2:-}"
            shift 2
            ;;
        --native)
            ARCH_ARGS=(--native)
            shift
            ;;
        --universal)
            ARCH_ARGS=(--universal)
            shift
            ;;
        --skip-open-smoke)
            OPEN_SMOKE=0
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

if [[ -z "$BUILD_NUMBER" ]]; then
    echo "Build number must be non-empty." >&2
    exit 64
fi

cd "$ROOT_DIR"

verify_finder_layout() {
    local dmg_path="$1"
    local report_path="$2"
    local tmp_dir
    local mount_point
    local background_size
    local status=0

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/focuspet-finder-layout.XXXXXX")"
    mount_point="$tmp_dir/mount"
    mkdir -p "$mount_point"

    hdiutil attach -nobrowse -readonly "$dmg_path" -mountpoint "$mount_point" >/dev/null
    if [[ ! -f "$mount_point/.background/background.png" ]]; then
        echo "DMG background image is missing: $mount_point/.background/background.png" > "$report_path"
        hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi
    background_size="$(sips -g pixelWidth -g pixelHeight "$mount_point/.background/background.png" 2>/dev/null | awk '/pixelWidth/ { width = $2 } /pixelHeight/ { height = $2 } END { print width "x" height }')"
    if [[ "$background_size" != "1440x920" ]]; then
        echo "DMG background image has unexpected size: $background_size" > "$report_path"
        hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
    fi

    osascript > "$report_path" <<OSA || status=$?
tell application "Finder"
    activate
    set dmgFolder to (POSIX file "$mount_point") as alias
    open dmgFolder
    repeat with windowAttempt from 1 to 10
        delay 0.3
        try
            set dmgWindow to container window of dmgFolder
            exit repeat
        end try
        if windowAttempt is 10 then error "Finder did not open the Focus Pet Installer window"
    end repeat
    repeat with attempt from 1 to 5
        set currentDmgView to current view of dmgWindow
        set viewOptions to icon view options of dmgWindow
        set currentIconSize to icon size of viewOptions
        set currentTextSize to text size of viewOptions
        if currentDmgView is icon view and currentIconSize is 96 and currentTextSize is 14 then exit repeat
        if attempt is 5 then
            if currentDmgView is not icon view then error "DMG window is not in icon view"
            if currentIconSize is not 96 then error "Unexpected DMG icon size (" & currentIconSize & ")"
            if currentTextSize is not 14 then error "Unexpected DMG text size (" & currentTextSize & ")"
        end if
        delay 0.4
    end repeat
    if position of item "Focus Pet.app" of dmgFolder is not {210, 230} then error "Focus Pet.app icon position is wrong"
    if position of item "Applications" of dmgFolder is not {510, 230} then error "Applications icon position is wrong"
    close dmgWindow
end tell
return "Finder layout passed for $dmg_path; background.png is 1440x920 Retina; app icon at {210, 230}; Applications icon at {510, 230}"
OSA

    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return "$status"
}

echo "Checking scripts..."
bash -n scripts/package-macos-app.sh scripts/package-dmg.sh scripts/verify-dmg-release.sh "$0"

echo "Building release target..."
swift build --configuration release

echo "Packaging local DMG with build $BUILD_NUMBER..."
PACKAGE_OUTPUT="$(
    scripts/package-dmg.sh \
        --local \
        --build "$BUILD_NUMBER" \
        --exclude-local-test-pets \
        "${ARCH_ARGS[@]}"
)"
printf '%s\n' "$PACKAGE_OUTPUT"

FINAL_DMG="$(
    printf '%s\n' "$PACKAGE_OUTPUT" |
        awk '/\/FocusPet-local-.*\.dmg$/ && $0 !~ /\/FocusPet-local\.dmg$/ { path = $0 } END { print path }'
)"

if [[ -z "$FINAL_DMG" || ! -f "$FINAL_DMG" ]]; then
    echo "Could not determine final DMG path from package output." >&2
    exit 70
fi

echo "Verifying DMG checksum..."
hdiutil verify "$FINAL_DMG"

echo "Verifying mounted DMG excludes local pet packs..."
scripts/verify-dmg-release.sh --local --expect-no-local-test-pets "$FINAL_DMG"

FINDER_REPORT="$FINAL_DMG.finder-layout.txt"
echo "Verifying Finder installer layout..."
verify_finder_layout "$FINAL_DMG" "$FINDER_REPORT"
cat "$FINDER_REPORT"

if [[ "$OPEN_SMOKE" -eq 1 ]]; then
    echo "Running installed-copy launch smoke..."
    rm -rf "$INSTALL_SMOKE_DIR"
    mkdir -p "$INSTALL_SMOKE_DIR"
    scripts/verify-dmg-release.sh \
        --local \
        --no-quarantine \
        --open-smoke \
        --expect-no-local-test-pets \
        --install-to "$INSTALL_SMOKE_DIR" \
        --replace \
        --report "$FINAL_DMG.install-open-smoke.txt" \
        "$FINAL_DMG"
fi

echo "Verified local DMG: $FINAL_DMG"
echo "Latest alias: $ROOT_DIR/dist/local/FocusPet-local.dmg"
echo "Finder layout report: $FINDER_REPORT"
