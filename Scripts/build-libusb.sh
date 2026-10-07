#!/bin/bash
set -euo pipefail

# Baut libusb und libusb-compat (die libusb-0.1-API, die pilot-link nutzt) aus
# festen Commits (Vendor/libusb/COMMIT, Vendor/libusb-compat/COMMIT) plus den
# Patches aus Vendor/<name>/patches, installiert nach .build/libusb/install.
# build-pilot-link.sh baut libpisock dagegen, build.sh bettet alles ein.
# Gebaut wird nur neu, wenn sich Commits oder Patches geändert haben.
#
# Voraussetzung (Homebrew): brew install autoconf automake libtool pkg-config

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$PROJECT_DIR/.build/libusb"
PREFIX="$WORK_DIR/install"
STAMP="$PREFIX/.stamp"

# "Commit + Prüfsumme der Patches" eines Vendor-Pakets
wanted() {
    local vendor="$PROJECT_DIR/Vendor/$1" patches
    shopt -s nullglob
    patches=("$vendor"/patches/*.patch)
    shopt -u nullglob
    # ${patches[@]+...}: ein leeres Array ist unter "set -u" in Bash 3.2 sonst ein Fehler
    echo "$(tr -d '[:space:]' < "$vendor/COMMIT") $(cat /dev/null ${patches[@]+"${patches[@]}"} | shasum -a 256 | cut -d' ' -f1)"
}

WANTED="libusb $(wanted libusb) libusb-compat $(wanted libusb-compat)"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ]; then
    echo "      libusb aktuell"
    exit 0
fi

# Quellbaum $1 aus Repo $2 sauber auf den Commit setzen und die Patches anwenden
checkout() {
    local name="$1" repo="$2" src="$WORK_DIR/$1-src" vendor="$PROJECT_DIR/Vendor/$1" commit patch
    commit="$(tr -d '[:space:]' < "$vendor/COMMIT")"
    echo "      Baue $name $commit ..." >&2
    if [ ! -d "$src/.git" ]; then
        rm -rf "$src"
        git clone --quiet "$repo" "$src"
    fi
    git -C "$src" fetch --quiet --tags origin
    git -C "$src" checkout --quiet --force --detach "$commit"
    git -C "$src" clean -fdxq
    shopt -s nullglob
    for patch in "$vendor"/patches/*.patch; do
        git -C "$src" apply "$patch"
        echo "      Patch: $(basename "$patch")" >&2
    done
    shopt -u nullglob
    echo "$src"
}

mkdir -p "$WORK_DIR"
rm -rf "$PREFIX"

SRC="$(checkout libusb https://github.com/libusb/libusb.git)"
(
    cd "$SRC"
    NOCONFIGURE=1 ./autogen.sh > "$WORK_DIR/libusb-autogen.log" 2>&1
    ./configure --prefix="$PREFIX" --disable-static > "$WORK_DIR/libusb-configure.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" > "$WORK_DIR/libusb-make.log" 2>&1
    make install > "$WORK_DIR/libusb-install.log" 2>&1
)

SRC="$(checkout libusb-compat https://github.com/libusb/libusb-compat-0.1.git)"
(
    cd "$SRC"
    NOCONFIGURE=1 ./autogen.sh > "$WORK_DIR/compat-autogen.log" 2>&1
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
        ./configure --prefix="$PREFIX" --disable-static > "$WORK_DIR/compat-configure.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" > "$WORK_DIR/compat-make.log" 2>&1
    make install > "$WORK_DIR/compat-install.log" 2>&1
)

echo "$WANTED" > "$STAMP"
echo "      libusb installiert: $PREFIX"
