#!/bin/bash
# Build Darko into a standalone .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="dist/Darko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/release/Darko" "$APP/Contents/MacOS/Darko"
cp "Sources/Darko/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"

echo "==> Built $APP"
echo "    Run: open $APP"
