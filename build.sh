#!/bin/bash
# Build Darko into a standalone .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="dist/Darko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/Darko" "$APP/Contents/MacOS/Darko"
cp "Sources/Darko/Info.plist" "$APP/Contents/Info.plist"
cp -R "Sources/Darko/Resources/Darko.icon" "$APP/Contents/Resources/Darko.icon"
cp "Sources/Darko/Resources/Darko.icns" "$APP/Contents/Resources/Darko.icns"

codesign --force --deep --sign - "$APP"

echo "==> Built $APP"
echo "    Run: open $APP"
