#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${WAYTTY_FLUTTER:-$(command -v flutter)}"
MODE="${1:---verify}"
case "$MODE" in run|--build|--verify|--release) ;; *) echo "Usage: $0 [run|--build|--verify|--release]" >&2; exit 2 ;; esac
if [[ ! -x "$FLUTTER_BIN" ]]; then FLUTTER_BIN="$(command -v flutter)"; fi
CONFIG=Debug
BUILD_FLAG=--debug
if [[ "$MODE" == --release ]]; then CONFIG=Release; BUILD_FLAG=--release; fi
cd "$ROOT_DIR/crossplatform/app"
"$FLUTTER_BIN" pub get
bash ../packages/yourssh_script_engine/native/build_macos.sh
"$FLUTTER_BIN" build macos "$BUILD_FLAG" --no-pub
APP_BUNDLE="$ROOT_DIR/dist/waytty.app"
mkdir -p "$ROOT_DIR/dist"
ditto "build/macos/Build/Products/$CONFIG/waytty.app" "$APP_BUNDLE"
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
if [[ ! -f "$ROOT_DIR/dist/AppIcon.icns" ]]; then swift "$ROOT_DIR/script/make_icon.swift" "$ROOT_DIR/dist"; fi
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
if [[ "$MODE" == --release ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ROOT_DIR/dist/waytty-macos.zip"
fi
if [[ "$MODE" != --build ]]; then
  pkill -x 'waytty' >/dev/null 2>&1 || true
  open -n "$APP_BUNDLE"
  if [[ "$MODE" == --verify ]]; then
    sleep 2
    pgrep -x 'waytty' >/dev/null
    echo "Launch verified: $APP_BUNDLE"
  fi
fi
echo "Built: $APP_BUNDLE"
