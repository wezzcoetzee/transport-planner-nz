#!/bin/zsh
# Builds a Release TransportPlannerNZ.app and packages it as dist/TransportPlannerNZ-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project TransportPlannerNZ.xcodeproj -scheme TransportPlannerNZ -configuration Release -derivedDataPath build/DerivedData build | grep -E "error|BUILD"

APP=build/DerivedData/Build/Products/Release/TransportPlannerNZ.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG=dist/TransportPlannerNZ-$VERSION.dmg

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/TransportPlannerNZ.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Transport Planner NZ" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
