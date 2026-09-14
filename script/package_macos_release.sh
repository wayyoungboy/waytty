#!/usr/bin/env bash
# Build a distributable development package without opening or stopping waytty.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${WAYTTY_FLUTTER:-$(command -v flutter)}"
VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$ROOT_DIR/crossplatform/app/pubspec.yaml")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
cd "$ROOT_DIR/crossplatform/app"
"$FLUTTER_BIN" pub get
bash ../packages/yourssh_script_engine/native/build_macos.sh
"$FLUTTER_BIN" build macos --release --no-pub
RELEASE_DIR="$ROOT_DIR/dist/release/$VERSION"
APP_BUNDLE="$RELEASE_DIR/waytty.app"
[[ ! -e "$APP_BUNDLE" ]] || { echo 'Release bundle already exists; use a fresh build directory' >&2; exit 1; }
mkdir -p "$RELEASE_DIR"
ditto build/macos/Build/Products/Release/waytty.app "$APP_BUNDLE"
cp ../packages/yourssh_script_engine/assets/native/macos/libqjsbridge.dylib "$APP_BUNDLE/Contents/Frameworks/"
cp ../LICENSE "$APP_BUNDLE/Contents/Resources/UPSTREAM-LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/"
mkdir -p "$APP_BUNDLE/Contents/Resources/third-party-licenses"
cp ../packages/yourssh_script_engine/native/QUICKJS-LICENSE.txt "$APP_BUNDLE/Contents/Resources/third-party-licenses/"
ditto assets/fonts/licenses "$APP_BUNDLE/Contents/Resources/third-party-licenses/fonts"
ditto assets/serial-licenses "$APP_BUNDLE/Contents/Resources/third-party-licenses/serial"
for package in ../packages/*; do
  if [[ -f "$package/LICENSE" ]]; then
    cp "$package/LICENSE" "$APP_BUNDLE/Contents/Resources/third-party-licenses/$(basename "$package")-LICENSE.txt"
  fi
done
swift "$ROOT_DIR/script/make_icon.swift" "$ROOT_DIR/dist"
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$APP_BUNDLE/Contents/Info.plist"
# Strip copied extended attributes, including quarantine and Finder metadata.
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Release bundle: $APP_BUNDLE"
echo 'Validate bundle privacy and architecture before creating or publishing a ZIP.'
