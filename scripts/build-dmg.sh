#!/bin/zsh
# Builds a Release NZTransportPlanner.app and packages it as dist/NZTransportPlanner-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project NZTransportPlanner.xcodeproj -scheme NZTransportPlanner -configuration Release -derivedDataPath build/DerivedData build | grep -E "error|BUILD"

APP=build/DerivedData/Build/Products/Release/NZTransportPlanner.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG=dist/NZTransportPlanner-$VERSION.dmg

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/NZTransportPlanner.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NZ Transport Planner" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
