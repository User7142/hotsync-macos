#!/bin/bash
set -euo pipefail

# HotSync.app Build-Script
# Baut die App und erstellt das .app Bundle

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="HotSync"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

PILOT_XFER="$HOME/.local/bin/pilot-xfer"
PILOT_INSTALL_USER="$HOME/.local/bin/pilot-install-user"

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

# 4. pilot-link Tools einbetten
echo "[4/6] Bette pilot-link Tools ein..."
EMBEDDED_LIBS=""

for TOOL_PATH in "$PILOT_XFER" "$PILOT_INSTALL_USER"; do
    TOOL_NAME=$(basename "$TOOL_PATH")
    if [ -f "$TOOL_PATH" ]; then
        cp "$TOOL_PATH" "$APP_BUNDLE/Contents/Resources/$TOOL_NAME"
        chmod +x "$APP_BUNDLE/Contents/Resources/$TOOL_NAME"
        echo "      $TOOL_NAME kopiert von $TOOL_PATH"

        # Abhängige Libraries prüfen und kopieren
        DYLIBS=$(otool -L "$TOOL_PATH" 2>/dev/null | grep -v "/usr/lib" | grep -v "/System" | grep -v "$TOOL_PATH" | awk '{print $1}' || true)
        if [ -n "$DYLIBS" ]; then
            mkdir -p "$APP_BUNDLE/Contents/Frameworks"
            for lib in $DYLIBS; do
                if [ -f "$lib" ] && ! echo "$EMBEDDED_LIBS" | grep -q "$(basename "$lib")"; then
                    cp "$lib" "$APP_BUNDLE/Contents/Frameworks/"
                    EMBEDDED_LIBS="$EMBEDDED_LIBS $(basename "$lib")"
                    echo "      Library kopiert: $(basename "$lib")"
                fi
            done
        fi
    else
        echo "      WARNUNG: $TOOL_NAME nicht gefunden unter $TOOL_PATH"
    fi
done

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
