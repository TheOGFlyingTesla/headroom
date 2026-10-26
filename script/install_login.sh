#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$HOME/Applications/Headroom.app"
if [[ -e "$DESTINATION" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
    if [[ "$IDENTIFIER" != org.headroom.app ]]; then
        echo 'A different application exists at the installation path; stopping.' >&2
        exit 1
    fi
fi
"$ROOT_DIR/script/build_and_run.sh" --build-only
"$ROOT_DIR/script/stop_app.sh"
mkdir -p "$HOME/Applications"
ditto "$ROOT_DIR/dist/Headroom.app" "$DESTINATION"
codesign --verify --strict "$DESTINATION"
"$DESTINATION/Contents/MacOS/Headroom" --enable-login
"$DESTINATION/Contents/MacOS/Headroom" --login-status
open "$DESTINATION"
