#!/bin/bash
# Builds, signs and packages Sporting Moments Clock for other people.
#
#   dist/make_release.sh                       build, sign, verify, make and sign the DMG
#   dist/make_release.sh --notarize PROFILE    the same, then notarise and staple
#
# PROFILE is a notarytool keychain profile, made once with
#   xcrun notarytool store-credentials PROFILE --apple-id <Apple ID> --team-id <Team ID>
# Output: dist/SportingMomentsClock-<version>.dmg. Build products and logs: dist/build/.

set -euo pipefail

# The signing identity: set SIGN_IDENTITY, or the first Developer ID Application certificate in the keychain is used.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate found. Set SIGN_IDENTITY." >&2; exit 1; }
DIST="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIST/../app"
BUILD="$DIST/build"
STAGE="$BUILD/stage"
APP="$STAGE/SportingMomentsClock.app"
SAVER="$APP/Contents/Resources/SportingMomentsClock.saver"

PROFILE=""
if [[ "${1:-}" == "--notarize" ]]; then
    PROFILE="${2:?usage: make_release.sh --notarize <keychain profile>}"
elif [[ $# -gt 0 ]]; then
    echo "usage: make_release.sh [--notarize <keychain profile>]" >&2
    exit 2
fi

step() { printf '\n== %s\n' "$*"; }

# Signs with Developer ID, the hardened runtime and a secure timestamp. No entitlements:
# the app is not sandboxed and needs no runtime exceptions.
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

make_dmg() {
    rm -f "$DMG"
    ln -sfn /Applications "$STAGE/Applications"
    hdiutil create -volname "Sporting Moments Clock" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm "$STAGE/Applications"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
}

# ---------------------------------------------------------------------------
step "Project"
cd "$APP_SRC"
xcodegen generate --quiet
mkdir -p "$BUILD"

step "Build (Release)"
build() {
    xcodebuild -project SportingMomentsClock.xcodeproj -scheme SportingMomentsClock -configuration Release \
        -derivedDataPath "$BUILD/DerivedData" -destination 'generic/platform=macOS' \
        ARCHS="$1" ONLY_ACTIVE_ARCH=NO build >"$BUILD/xcodebuild.log" 2>&1
}
if build "arm64 x86_64"; then
    echo "Universal build (arm64 and x86_64)."
else
    echo "The universal build failed (see $BUILD/xcodebuild.log); building for arm64 only."
    build "arm64" || { tail -30 "$BUILD/xcodebuild.log"; exit 1; }
    echo "arm64 only build."
fi
grep '^warning: make_credits' "$BUILD/xcodebuild.log" | sort -u || true

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$BUILD/DerivedData/Build/Products/Release/SportingMomentsClock.app" "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$DIST/SportingMomentsClock-$VERSION.dmg"
echo "Version $VERSION ($BUILD_NUMBER)"
lipo -info "$APP/Contents/MacOS/SportingMomentsClock" "$SAVER/Contents/MacOS/SportingMomentsClock"

# ---------------------------------------------------------------------------
step "Sign, inside out"
# 1. Nested code inside the screen saver (none today), then the saver bundle, which signs its executable.
find "$SAVER/Contents" -path "$SAVER/Contents/MacOS" -prune -o \( -name "*.dylib" -o -name "*.framework" \) -print0 \
    | xargs -0 -r -n1 bash -c 'codesign --force --options runtime --timestamp --sign "$0" "$1"' "$IDENTITY"
sign "$SAVER"
# 2. Frameworks and libraries inside the app (none today: MomentsCore is linked statically).
if [[ -d "$APP/Contents/Frameworks" ]]; then
    find "$APP/Contents/Frameworks" -depth \( -name "*.dylib" -o -name "*.framework" \) -print0 \
        | xargs -0 -r -n1 bash -c 'codesign --force --options runtime --timestamp --sign "$0" "$1"' "$IDENTITY"
fi
# 3. The app.
sign "$APP"

# ---------------------------------------------------------------------------
step "Verify"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Format|Authority=Developer|TeamIdentifier|Timestamp|Runtime Version|CodeDirectory)'
codesign --display --verbose=2 "$SAVER" 2>&1 | grep -E '^(Identifier|TeamIdentifier|Timestamp|CodeDirectory)'
ENTITLEMENTS=$(codesign --display --entitlements - --xml "$APP" 2>/dev/null; codesign --display --entitlements - --xml "$SAVER" 2>/dev/null)
if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
    echo "get-task-allow is present; a release must not carry it." >&2
    exit 1
fi
echo "Entitlements: none (no get-task-allow)."
echo "spctl (rejected until notarised):"
spctl --assess --type execute -vv "$APP" 2>&1 || true

step "Install check"
# Installs the signed saver into a temporary folder the way the app does, then checks its signature.
CHECK="$BUILD/install_check"
rm -rf "$CHECK"
mkdir -p "$CHECK/Screen Savers"
CORE="$APP_SRC/Sources/MomentsCore"
swiftc -O -parse-as-library -o "$CHECK/verify_install" "$DIST/verify_install.swift" \
    "$CORE/SaverInstaller.swift" "$CORE/SharedSettings.swift" "$CORE/ClockSettings.swift" "$CORE/AppIdentity.swift"
"$CHECK/verify_install" "$APP" "$CHECK/Screen Savers"
codesign --verify --deep --strict --verbose=2 "$CHECK/Screen Savers/SportingMomentsClock.saver"
rm -rf "$CHECK"

# ---------------------------------------------------------------------------
step "Disk image"
make_dmg
codesign --verify --verbose=2 "$DMG"
echo "spctl (rejected until notarised):"
spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 || true
ls -lh "$DMG" | awk '{print $5, $9}'

# ---------------------------------------------------------------------------
# Notarisation. Runs only with --notarize PROFILE. Sends the app and the DMG to Apple.
if [[ -z "$PROFILE" ]]; then
    printf '\nNot notarised. To notarise and staple, run:\n  dist/make_release.sh --notarize <keychain profile>\n'
    exit 0
fi

notarize() {
    local log="$BUILD/notary_$(basename "$1").log"
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait | tee "$log"
    grep -q "status: Accepted" "$log" || {
        echo "Notarisation of $1 was not accepted. Details: xcrun notarytool log <submission id> --keychain-profile $PROFILE" >&2
        exit 1
    }
}

step "Notarise the app"
# The app first, so the copy dragged out of the DMG carries its own ticket and opens offline.
ditto -c -k --keepParent "$APP" "$BUILD/SportingMomentsClock.zip"
notarize "$BUILD/SportingMomentsClock.zip"
xcrun stapler staple "$APP"

step "Notarise the disk image"
make_dmg
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Gatekeeper"
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
ls -lh "$DMG" | awk '{print $5, $9}'
