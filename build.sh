#!/bin/bash
# Compile MacWidget sans Xcode (Command Line Tools suffisent), signe et installe.
#   ./build.sh            → compile + installe dans /Applications + lance
#   ./build.sh --no-install
#   SIGN_IDENTITY="Apple Development: …" ./build.sh   (sinon certificat local stable, voir tools/)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=MacWidget
BUILD=build
# Bundle assemblé hors de Documents : la synchro iCloud y remet des attributs Finder
# que codesign refuse (« resource fork, Finder information… »).
STAGE="$HOME/Library/Caches/MacWidget-build"
APP="$STAGE/$APP_NAME.app"
EXT="$APP/Contents/PlugIns/MacWidgetWidgets.appex"
ARCH=$(uname -m)
# Sans Xcode, les plugins de macros SwiftUI (dont @State depuis macOS 27) sont absents :
# on prend le SDK 26.x des Command Line Tools s'il existe.
SDK_DIR=/Library/Developer/CommandLineTools/SDKs
SDK=$(ls -d "$SDK_DIR"/MacOSX26.*.sdk "$SDK_DIR"/MacOSX26.sdk 2>/dev/null | sort -V | tail -1 || true)
[ -n "$SDK" ] || SDK=$(xcrun --sdk macosx --show-sdk-path)
SIGN="${SIGN_IDENTITY:-MacWidget Local Signing}"
FLAGS=(-O -whole-module-optimization -swift-version 5 -sdk "$SDK" -target "$ARCH-apple-macos14.0")

echo "▸ Nettoyage"
rm -rf "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"

echo "▸ Icône"
if [ ! -f "$BUILD/AppIcon.icns" ]; then
  swiftc -O tools/MakeIcon.swift -o "$BUILD/make-icon"
  "$BUILD/make-icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Extension widgets"
# Point d'entrée d'extension (ce qu'Xcode ajoute tout seul) : il initialise le type
# d'extension avant d'appeler le main de WidgetBundle, sinon chronod la voit planter.
swiftc "${FLAGS[@]}" -application-extension -parse-as-library -module-name MacWidgetWidgets \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Shared/*.swift Widgets/*.swift -o "$EXT/Contents/MacOS/MacWidgetWidgets"
# Numéro de build unique : sinon macOS garde en cache l'ancienne liste de widgets.
BUILD_NUMBER=$(date +%Y%m%d%H%M%S)
cp Resources/Widgets-Info.plist "$EXT/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$EXT/Contents/Info.plist"

echo "▸ Application"
swiftc "${FLAGS[@]}" -module-name MacWidget \
  Shared/*.swift $(ls Widgets/*.swift | grep -v WidgetsBundle.swift) App/*.swift App/UI/*.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signature ($SIGN)"
xattr -cr "$APP"
KEYCHAIN_ARGS=()
if [ -z "${SIGN_IDENTITY:-}" ]; then
  KEYCHAIN_ARGS=(--keychain "$(tools/signing-identity.sh)")
fi
codesign --force --sign "$SIGN" "${KEYCHAIN_ARGS[@]}" --entitlements Resources/Widgets.entitlements --timestamp=none "$EXT"
codesign --force --sign "$SIGN" "${KEYCHAIN_ARGS[@]}" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

[ "${1:-}" = "--no-install" ] && { echo "✓ $APP"; exit 0; }

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
echo "▸ Installation dans $DEST"
pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "$DEST/$APP_NAME.app"
cp -R "$APP" "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP_NAME.app"
pluginkit -a "$DEST/$APP_NAME.app/Contents/PlugIns/MacWidgetWidgets.appex" 2>/dev/null || true
# Arrête l'ancienne extension encore en mémoire ; macOS relance la nouvelle à la demande.
pkill -f "MacWidgetWidgets.appex/Contents/MacOS/MacWidgetWidgets" 2>/dev/null || true
open "$DEST/$APP_NAME.app"
echo "✓ MacWidget installé et lancé"
