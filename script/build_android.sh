#!/usr/bin/env bash
# Build Android release APKs (split ABI + universal) and an AAB.
# Signing: if crossplatform/app/android/key.properties exists (or CI writes it
# from ANDROID_KEYSTORE_* secrets), the Gradle release config uses that
# keystore. Otherwise Flutter/Gradle fall back to the debug keystore and this
# script prints a clear warning.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${WAYTTY_FLUTTER:-flutter}"
APP_DIR="$ROOT_DIR/crossplatform/app"
ANDROID_DIR="$APP_DIR/android"
VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$APP_DIR/pubspec.yaml")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }

CLOUD_DEFINE=(--dart-define="WAYTTY_CLOUD_URL=${WAYTTY_CLOUD_URL:-}")
SIGNED=0
if [[ -f "$ANDROID_DIR/key.properties" ]]; then
  SIGNED=1
  echo "Android release signing: using $ANDROID_DIR/key.properties"
else
  echo "::warning::Android release signing secrets/key.properties absent; falling back to debug signing. Artifacts must not be published as production releases."
fi

cd "$APP_DIR"
"$FLUTTER_BIN" pub get

# Do not pass --no-pub to release builds: Flutter only strips integration_test
# (and other dev_dependency plugins) from GeneratedPluginRegistrant when pub
# runs as part of the build (releaseMode=true). Using --no-pub after a plain
# `flutter pub get` leaves integration_test registered and breaks release javac.
# Split-per-ABI plus a fat/universal APK. Target platforms cover current phones/tablets.
"$FLUTTER_BIN" build apk --release \
  --split-per-abi \
  "${CLOUD_DEFINE[@]}"
"$FLUTTER_BIN" build apk --release \
  "${CLOUD_DEFINE[@]}"
"$FLUTTER_BIN" build appbundle --release \
  "${CLOUD_DEFINE[@]}"

OUT_DIR="$ROOT_DIR/dist/release/$VERSION"
mkdir -p "$OUT_DIR" "$ROOT_DIR/dist"
APK_DIR="$APP_DIR/build/app/outputs/flutter-apk"
AAB_PATH="$APP_DIR/build/app/outputs/bundle/release/app-release.aab"

copy_apk() {
  local src="$1" dest_name="$2"
  [[ -f "$src" ]] || { echo "Missing APK: $src" >&2; exit 1; }
  cp "$src" "$OUT_DIR/$dest_name"
  cp "$src" "$ROOT_DIR/dist/$dest_name"
}

copy_apk "$APK_DIR/app-armeabi-v7a-release.apk" "waytty-$VERSION-android-armeabi-v7a.apk"
copy_apk "$APK_DIR/app-arm64-v8a-release.apk" "waytty-$VERSION-android-arm64-v8a.apk"
copy_apk "$APK_DIR/app-x86_64-release.apk" "waytty-$VERSION-android-x86_64.apk"
copy_apk "$APK_DIR/app-release.apk" "waytty-$VERSION-android-universal.apk"

if [[ -f "$AAB_PATH" ]]; then
  cp "$AAB_PATH" "$OUT_DIR/waytty-$VERSION-android.aab"
  cp "$AAB_PATH" "$ROOT_DIR/dist/waytty-$VERSION-android.aab"
fi

(
  cd "$OUT_DIR"
  rm -f SHA256SUMS-android.txt
  for f in waytty-"$VERSION"-android-*.apk waytty-"$VERSION"-android.aab; do
    [[ -f "$f" ]] || continue
    sha256sum "$f" >> SHA256SUMS-android.txt
  done
)

SIGNING_NOTE='release-keystore'
if [[ "$SIGNED" -eq 0 ]]; then
  SIGNING_NOTE='debug-keystore-fallback'
fi
{
  echo "product=waytty"
  echo "version=$VERSION"
  echo "platform=android"
  echo "signing=$SIGNING_NOTE"
  echo "artifacts=$(cd "$OUT_DIR" && echo waytty-$VERSION-android-*.apk waytty-$VERSION-android.aab 2>/dev/null | tr '\n' ' ')"
  echo "built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "note=CI packaging only. Target-device / USB Host acceptance is separate."
} > "$OUT_DIR/BUILD_INFO-android.txt"

echo "Android artifacts in $OUT_DIR"
ls -lh "$OUT_DIR"
if [[ "$SIGNED" -eq 0 ]]; then
  echo "WARNING: debug-signed Android build; supply ANDROID_KEYSTORE_* secrets for production."
fi
