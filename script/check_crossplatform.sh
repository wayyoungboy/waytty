#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${WAYTTY_FLUTTER:-$HOME/.local/share/xtn-toolchains/flutter/bin/flutter}"
if [[ ! -x "$FLUTTER_BIN" ]]; then FLUTTER_BIN="$(command -v flutter)"; fi
python3 "$ROOT_DIR/script/generate_l10n.py" --check
cd "$ROOT_DIR/crossplatform/app"
"$FLUTTER_BIN" pub get
"$(dirname "$FLUTTER_BIN")/dart" run tool/audit_l10n.dart
"$FLUTTER_BIN" analyze --no-pub
"$FLUTTER_BIN" test --no-pub --reporter expanded
