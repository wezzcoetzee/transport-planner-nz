#!/bin/zsh
# Builds a Release NZTransportPlanner.app and packages it as dist/NZTransportPlanner-<version>.dmg (with an Applications shortcut) and .zip.
# Usage: build-dmg.sh [version]. Without a version, MARKETING_VERSION from project.yml is used.
set -euo pipefail
VERSION_OVERRIDE=(${1:+MARKETING_VERSION=$1})
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project NZTransportPlanner.xcodeproj -scheme NZTransportPlanner -configuration Release -derivedDataPath build/DerivedData "${VERSION_OVERRIDE[@]}" build | grep -E "error|BUILD"

APP=build/DerivedData/Build/Products/Release/NZTransportPlanner.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG=dist/NZTransportPlanner-$VERSION.dmg
ZIP=dist/NZTransportPlanner-$VERSION.zip

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/NZTransportPlanner.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NZ Transport Planner" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
