#!/bin/bash
set -euo pipefail

# Baut libpisock aus pilot-link: fester Commit (Vendor/pilot-link/COMMIT) plus
# die Patches aus Vendor/pilot-link/patches (falls es welche gibt - Fixes, die
# upstream noch fehlen), installiert nach
# .build/pilot-link/install. build.sh bettet das Ergebnis in die App ein.
# Gebaut wird nur neu, wenn sich Commit oder Patches geändert haben.
#
# libusb und libusb-compat kommen aus build-libusb.sh (.build/libusb/install),
# nicht aus Homebrew.
#
# Voraussetzung (Homebrew): brew install autoconf automake libtool pkg-config popt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/Vendor/pilot-link"
WORK_DIR="$PROJECT_DIR/.build/pilot-link"
SRC_DIR="$WORK_DIR/src"
PREFIX="$WORK_DIR/install"
STAMP="$PREFIX/.stamp"
REPO="https://github.com/desrod/pilot-link.git"
LIBUSB_PREFIX="$PROJECT_DIR/.build/libusb/install"

"$SCRIPT_DIR/build-libusb.sh"

COMMIT="$(tr -d '[:space:]' < "$VENDOR_DIR/COMMIT")"
shopt -s nullglob
PATCHES=("$VENDOR_DIR"/patches/*.patch)
shopt -u nullglob
# ${PATCHES[@]+...}: ein leeres Array ist unter "set -u" in Bash 3.2 sonst ein Fehler
# mit dem Stand von libusb: ändert der sich, wird libpisock neu dagegen gebaut
WANTED="$COMMIT $(cat /dev/null ${PATCHES[@]+"${PATCHES[@]}"} | shasum -a 256 | cut -d' ' -f1) $(cat "$LIBUSB_PREFIX/.stamp")"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ]; then
    echo "      pilot-link aktuell ($COMMIT + ${#PATCHES[@]} Patches)"
    exit 0
fi

echo "      Baue pilot-link $COMMIT + ${#PATCHES[@]} Patches ..."
if [ ! -d "$SRC_DIR/.git" ]; then
    rm -rf "$SRC_DIR"
    git clone --quiet "$REPO" "$SRC_DIR"
fi
git -C "$SRC_DIR" fetch --quiet origin
# Der Quellbaum gehört nur diesem Skript: sauber auf den Commit setzen
git -C "$SRC_DIR" checkout --quiet --force --detach "$COMMIT"
git -C "$SRC_DIR" clean -fdxq
for patch in ${PATCHES[@]+"${PATCHES[@]}"}; do
    git -C "$SRC_DIR" apply "$patch"
    echo "      Patch: $(basename "$patch")"
done

BREW="$(brew --prefix)"
rm -rf "$PREFIX"
(
    cd "$SRC_DIR"
    NOCONFIGURE=1 sh ./autogen.sh > "$WORK_DIR/autogen.log" 2>&1
    # unser libusb vor Homebrews (das liefert nur noch popt)
    PKG_CONFIG_PATH="$LIBUSB_PREFIX/lib/pkgconfig" \
    CPPFLAGS="-I$LIBUSB_PREFIX/include -I$BREW/include" LDFLAGS="-L$LIBUSB_PREFIX/lib -L$BREW/lib" \
        ./configure --prefix="$PREFIX" --enable-libusb > "$WORK_DIR/configure.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" -C libpisock > "$WORK_DIR/make.log" 2>&1
    make -C libpisock install > "$WORK_DIR/install.log" 2>&1
    make -C include install >> "$WORK_DIR/install.log" 2>&1
)
echo "$WANTED" > "$STAMP"
echo "      pilot-link installiert: $PREFIX"
