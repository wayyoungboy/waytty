#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="XTerminalNative"
BUNDLE_ID="dev.local.XTerminalNative"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry|--build]" >&2; exit 2;; esac

# Only terminate our exact executable; never touch XTerminal or other terminals.
if [[ "$MODE" != "--build" ]]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
swift build --product "$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
for resource in "$BUILD_DIR"/*.bundle; do
    [[ -d "$resource" ]] && ditto "$resource" "$APP_BUNDLE/Contents/Resources/$(basename "$resource")"
done
if [[ ! -f "$ROOT_DIR/dist/AppIcon.icns" ]]; then swift "$ROOT_DIR/script/make_icon.swift" "$ROOT_DIR/dist"; fi
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>XTerminalNative</string>
<key>CFBundleIdentifier</key><string>dev.local.XTerminalNative</string>
<key>CFBundleName</key><string>XTerminal Native</string>
<key>CFBundleDisplayName</key><string>XTerminal Native</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>连接局域网中的 SSH 和 SFTP 服务器。</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_BUNDLE" >/dev/null
case "$MODE" in
    --build) echo "Built $APP_BUNDLE" ;;
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
    --logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
    --telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
    --verify) open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "Build and launch verified: $APP_BUNDLE" ;;
    run) open -n "$APP_BUNDLE" ;;
esac
