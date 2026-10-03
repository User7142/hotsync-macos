#!/bin/bash
set -euo pipefail

# HotSync.app Build-Script
# Baut die App und erstellt das .app Bundle

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="HotSync"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

# pilot-link-Installation (Prefix mit include/ und lib/): hotsync-session wird gegen ihre
# libpisock gebaut (abweichender Ort per Umgebungsvariable PILOT_PREFIX). Muss master >= c32f9eed
# sein, sonst findet USB unter macOS keinen Palm.
PILOT_PREFIX="${PILOT_PREFIX:-$HOME/.local}"
SESSION_TOOL="$BUILD_DIR/release/hotsync-session"

echo "=== HotSync Build ==="
echo "Projekt: $PROJECT_DIR"
echo ""

# 1. Swift Build
echo "[1/6] Kompiliere..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

EXECUTABLE="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    echo "FEHLER: Executable nicht gefunden unter $EXECUTABLE"
    exit 1
fi
echo "      Executable: $EXECUTABLE"

# 2. App-Bundle erstellen
echo "[2/6] Erstelle App-Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Executable kopieren
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist kopieren
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 3. App-Icon
echo "[3/6] Kopiere App-Icon..."
ICON_FILE="$PROJECT_DIR/Resources/AppIcon.icns"
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "      Icon kopiert"
else
    echo "      WARNUNG: AppIcon.icns nicht gefunden. Generiere..."
    swift "$SCRIPT_DIR/generate-icon.swift" "$PROJECT_DIR" 2>&1
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        echo "      Icon generiert und kopiert"
    fi
fi

# 4. hotsync-session bauen und einbetten
# Das Werkzeug und ALLE seine Nicht-System-Bibliotheken (rekursiv: libpisock, libusb-compat,
# libusb-1.0, ...) wandern ins Bundle; alle Verweise werden auf @rpath umgeschrieben. So läuft die
# App auch auf einem Mac ohne Homebrew bzw. ohne pilot-link in ~/.local.
echo "[4/6] Baue hotsync-session und bette es ein..."
if [ ! -f "$PILOT_PREFIX/include/pi-dlp.h" ] || [ ! -f "$PILOT_PREFIX/lib/libpisock.dylib" ]; then
    echo "      FEHLER: pilot-link nicht gefunden unter $PILOT_PREFIX (include/pi-dlp.h, lib/libpisock.dylib)"
    exit 1
fi
clang -std=c99 -Wall -Wextra -Werror -O2 \
    -I"$PILOT_PREFIX/include" -L"$PILOT_PREFIX/lib" -lpisock \
    -o "$SESSION_TOOL" "$PROJECT_DIR/Tools/hotsync-session/hotsync-session.c"
echo "      hotsync-session gebaut"
FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

# Nicht-System-Abhängigkeiten eines Mach-O (ohne die eigene Install-ID)
non_system_deps() {
    local own_id
    own_id=$(otool -D "$1" 2>/dev/null | tail -n +2)
    otool -L "$1" | tail -n +2 | awk '{print $1}' \
        | grep -v -E '^(/usr/lib/|/System/|@)' \
        | grep -v -x -F "${own_id:-__none__}" || true
}

# Bibliothek einsammeln (rekursiv), Pfad der Kopie merken
embed_lib() {
    local lib="$1" name
    name=$(basename "$lib")
    [ -f "$FRAMEWORKS/$name" ] && return 0
    if [ ! -f "$lib" ]; then
        echo "      FEHLER: Bibliothek $lib nicht gefunden"
        exit 1
    fi
    cp "$lib" "$FRAMEWORKS/$name"
    chmod u+w "$FRAMEWORKS/$name"
    echo "      Library kopiert: $name"
    local dep
    for dep in $(non_system_deps "$lib"); do
        embed_lib "$dep"
    done
}

# Verweise einer Datei auf eingebettete Bibliotheken umschreiben
relink() {
    local file="$1" dep
    for dep in $(non_system_deps "$file"); do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file" 2>/dev/null
    done
}

TOOL="$APP_BUNDLE/Contents/Resources/hotsync-session"
cp "$SESSION_TOOL" "$TOOL"
chmod +x "$TOOL"
chmod u+w "$TOOL"
for dep in $(non_system_deps "$SESSION_TOOL"); do
    embed_lib "$dep"
done
relink "$TOOL"
# Das Werkzeug liegt in Contents/Resources, die Bibliotheken in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$TOOL" 2>/dev/null

for LIB in "$FRAMEWORKS"/*.dylib; do
    [ -f "$LIB" ] || continue
    install_name_tool -id "@rpath/$(basename "$LIB")" "$LIB" 2>/dev/null
    relink "$LIB"
done

# Nach install_name_tool sind die Signaturen ungültig: jede Datei einzeln ad hoc neu signieren
for BIN in "$FRAMEWORKS"/*.dylib "$APP_BUNDLE/Contents/Resources/hotsync-session"; do
    [ -f "$BIN" ] && codesign --force --sign - "$BIN" 2>&1
done

# Lizenzen der eingebetteten Bibliotheken mitliefern
if [ -d "$PROJECT_DIR/Resources/ThirdPartyLicenses" ]; then
    cp -R "$PROJECT_DIR/Resources/ThirdPartyLicenses" "$APP_BUNDLE/Contents/Resources/"
    echo "      Lizenzen kopiert: ThirdPartyLicenses/"
fi

# Prüfen: kein eingebettetes Binary darf noch auf etwas außerhalb von System und Bundle zeigen
LEAKS=""
for BIN in "$FRAMEWORKS"/*.dylib "$APP_BUNDLE/Contents/Resources/hotsync-session"; do
    [ -f "$BIN" ] || continue
    BAD=$(otool -L "$BIN" | tail -n +2 | awk '{print $1}' | grep -v -E '^(/usr/lib/|/System/|@rpath/)' || true)
    [ -n "$BAD" ] && LEAKS="$LEAKS\n  $(basename "$BIN"): $BAD"
done
if [ -n "$LEAKS" ]; then
    echo -e "      FEHLER: Verweise außerhalb des Bundles:$LEAKS"
    exit 1
fi
echo "      Alle Verweise zeigen auf das Bundle (@rpath) oder das System"

# 5. Code-Signing (ad-hoc)
echo "[5/6] Code-Signing (ad-hoc)..."
codesign --deep --force --sign - \
    --entitlements "$PROJECT_DIR/Resources/Entitlements.plist" \
    "$APP_BUNDLE" 2>&1
echo "      Signiert"

# 6. Verifikation
echo "[6/6] Verifiziere..."
codesign -v "$APP_BUNDLE" 2>&1 && echo "      Code-Signatur OK" || echo "      WARNUNG: Signatur-Check fehlgeschlagen"

echo ""
echo "=== Build erfolgreich ==="
echo "App: $APP_BUNDLE"
echo ""
echo "Starten mit:"
echo "  open $APP_BUNDLE"
echo ""
echo "Oder zum Installieren:"
echo "  cp -R $APP_BUNDLE /Applications/"
