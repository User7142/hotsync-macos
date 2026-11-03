#!/bin/bash
# Builds palmsync-calendar and runs it as a small app bundle through
# LaunchServices. A bare command-line tool started by another app (an
# editor, an agent) gets no Calendar access prompt from macOS, because the
# access is attributed to whatever started it; as an app bundle of its own
# the tool is asked about once and remembered. From Terminal the bare binary
# .build/debug/palmsync-calendar works just as well.
#
#   Scripts/palmsync-calendar.sh --list
#   Scripts/palmsync-calendar.sh --calendar Personal --device "Zoë Leto"
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product palmsync-calendar >/dev/null

APP="$PWD/.build/palmsync-calendar.app"   # open -a wants an absolute path
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/palmsync-calendar "$APP/Contents/MacOS/"
sed 's#</dict>#    <key>CFBundleExecutable</key><string>palmsync-calendar</string>\
    <key>CFBundlePackageType</key><string>APPL</string>\
    <key>LSUIElement</key><true/>\
</dict>#' Resources/palmsync-calendar-Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null

OUT=$(mktemp) ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT
open -W -n --stdout="$OUT" --stderr="$ERR" -a "$APP" --args "$@"
cat "$OUT"
cat "$ERR" >&2
