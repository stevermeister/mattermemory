#!/bin/bash
# Builds MatterMemory.app into ./build. Usage: scripts/build-app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/MatterMemory.app
swift build -c release 2>&1 | grep -Ev "^\[[0-9]+/[0-9]+\]|^Compiling|^Emitting|^Linking|^Write auxiliary" || true
BIN=$(swift build -c release --show-bin-path)/MatterMemory
swift build -c release >/dev/null 2>&1 || { echo "build failed"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MatterMemory"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

if [ ! -f build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"
echo "built $APP ($(du -sh "$APP" | cut -f1))"
[ "${1:-}" = "--run" ] && open "$APP" || true
