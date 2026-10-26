#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--preview|--build-only|--debug|--logs|--telemetry) ;; *) echo "Unknown mode: $MODE" >&2; exit 2;; esac
# A build-only request never stops a running app.
if [[ "$MODE" != --build-only ]]; then "$ROOT_DIR/script/stop_app.sh"; fi
swift build
BUILD_DIR="$(swift build --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/Headroom.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/Headroom" "$APP_BUNDLE/Contents/MacOS/Headroom"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Headroom</string>
<key>CFBundleIdentifier</key><string>org.headroom.app</string>
<key>CFBundleName</key><string>Headroom</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_BUNDLE"
case "$MODE" in
    --build-only) exit 0 ;;
    --preview) open "$APP_BUNDLE" --args --show ;;
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/Headroom" ;;
    --logs|--telemetry)
        open "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate 'process == "Headroom"'
        ;;
    *)
        open "$APP_BUNDLE"
        if [[ "$MODE" == --verify ]]; then sleep 1; pgrep -x Headroom >/dev/null; fi
        ;;
esac
