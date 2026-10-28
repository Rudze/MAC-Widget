#!/bin/bash
# Crée une fois pour toutes un certificat de signature local (auto-signé) dans un trousseau dédié.
# Pourquoi : une signature « ad hoc » change à chaque compilation, donc macOS prend chaque build
# pour une nouvelle app et redemande l'accès au calendrier / Bluetooth. Avec un certificat stable,
# l'autorisation donnée une fois est conservée, même après recompilation ou redémarrage.
# Affiche le chemin du trousseau à passer à codesign.
set -euo pipefail

NAME="MacWidget Local Signing"
DIR="$HOME/Library/Application Support/MacWidget-Signing"
KEYCHAIN="$DIR/signing.keychain-db"
PASSWORD_FILE="$DIR/password"

mkdir -p "$DIR"
chmod 700 "$DIR"

if [ ! -f "$KEYCHAIN" ]; then
  [ -f "$PASSWORD_FILE" ] || { openssl rand -hex 24 > "$PASSWORD_FILE"; chmod 600 "$PASSWORD_FILE"; }
  PASSWORD=$(cat "$PASSWORD_FILE")
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/cert.cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout pass:"$PASSWORD" 2>/dev/null
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
echo "$KEYCHAIN"
