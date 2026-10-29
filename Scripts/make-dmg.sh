#!/bin/bash
set -euo pipefail
# Packs HotSync.app into a disk image for distribution: the app next to a link to
# /Applications, so installing is "open the image, drag HotSync into Applications".
#
#   Scripts/make-dmg.sh [HotSync.app] [output.dmg]
#
# Defaults: the HotSync.app that build.sh leaves in the project root, and
# HotSync-<version>-macos-<arch>.dmg next to it, where <version> is the bundle's
# CFBundleShortVersionString and <arch> is arm64, x86_64 or universal, read from the
# main executable. The image is compressed (UDZO) and verified.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP="${1:-$PROJECT_DIR/HotSync.app}"

if [ ! -d "$APP/Contents/MacOS" ]; then
    echo "ERROR: $APP is not an app bundle (run Scripts/build.sh first)" >&2
    exit 1
fi

APP_NAME="$(basename "$APP" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) ARCH_TAG="universal" ;;
    *) ARCH_TAG="$(echo "$ARCHS" | tr ' ' '-')" ;;
esac
DMG="${2:-$PROJECT_DIR/$APP_NAME-$VERSION-macos-$ARCH_TAG.dmg}"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hotsync-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

echo "=== $APP_NAME $VERSION ($ARCHS) -> $(basename "$DMG")"
# ditto keeps resource forks, extended attributes and the code signature intact
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
hdiutil verify -quiet "$DMG"

echo "    $(du -h "$DMG" | cut -f1 | tr -d ' ')  $DMG"
