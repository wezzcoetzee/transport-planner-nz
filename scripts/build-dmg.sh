#!/bin/zsh
# Builds a Release WhenToLeave.app and packages it as dist/WhenToLeave-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project WhenToLeave.xcodeproj -scheme WhenToLeave -configuration Release -derivedDataPath build/DerivedData build | grep -E "error|BUILD"

APP=build/DerivedData/Build/Products/Release/WhenToLeave.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG=dist/WhenToLeave-$VERSION.dmg

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/WhenToLeave.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "When To Leave" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
