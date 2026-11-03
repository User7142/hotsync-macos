#!/bin/bash
# Legt ein selbst signiertes Zertifikat "HotSync Development" im Schlüsselbund
# an, mit dem build.sh die App signiert. Ad hoc signiert ("-") bekommt jeder
# Build eine neue Signatur, und macOS fragt nach jedem Build wieder nach dem
# Zugriff auf Kalender und Kontakte; mit einer festen Identität bleibt die
# Freigabe erhalten. Einmal ausführen; macOS fragt beim Importieren und beim
# Vertrauen nach dem Anmeldepasswort.
#
#   Scripts/make-signing-identity.sh
#   CODESIGN_IDENTITY="HotSync Development" Scripts/build.sh   (oder in .signing-identity)
set -euo pipefail

NAME="${1:-HotSync Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
    echo "Identität \"$NAME\" ist schon im Schlüsselbund."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" > /dev/null 2>&1

openssl pkcs12 -export -legacy -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout pass:hotsync 2>/dev/null \
    || openssl pkcs12 -export -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout pass:hotsync

# -T: codesign darf den Schlüssel ohne Rückfrage benutzen
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P hotsync -T /usr/bin/codesign -T /usr/bin/security
# Das Zertifikat als vertrauenswürdig für Code-Signierung eintragen (fragt nach dem Passwort)
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "$NAME" > "$(dirname "$0")/../.signing-identity"
echo "Identität \"$NAME\" angelegt; build.sh signiert ab jetzt damit (.signing-identity)."
security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME" || echo "WARNUNG: codesign sieht die Identität noch nicht"
