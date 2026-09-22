#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${WAYTTY_FLUTTER:-flutter}"
cd "$ROOT_DIR/crossplatform/app"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --debug --no-pub \
  "--dart-define=WAYTTY_CLOUD_URL=${WAYTTY_CLOUD_URL:-}" \
# Debug signing is deliberate until an Android release keystore is supplied.
mkdir -p "$ROOT_DIR/dist"
cp build/app/outputs/flutter-apk/app-debug.apk "$ROOT_DIR/dist/waytty-android-debug.apk"
