#!/bin/zsh
# Renders every screen and state to screenshots/raw/mac, then frames the App Store set listed in
# screenshots/manifest.json into screenshots/framed/mac at 2880x1800 with headless Chrome.
#
# The renders use a fixed demo commute timed from "now", so TZ pins the clock to the 4 pm hour (next to the default
# 4:40 to 5:30 pm leave window; Etc/GMT zones are whole hours, sign inverted) and times use the en_NZ locale in
# 12-hour form, whatever the Mac is set to.
set -euo pipefail
cd "$(dirname "$0")/.."

RAW=screenshots/raw/mac
FRAMED=screenshots/framed/mac
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

xcodegen generate >/dev/null
xcodebuild -project NZTransportPlanner.xcodeproj -scheme NZTransportPlanner -configuration Debug -derivedDataPath build/DerivedData build | grep -E "error:|BUILD"

PINNED_TZ=$(python3 -c '
import datetime as d
hours = (16 - d.datetime.now(d.timezone.utc).hour) % 24
if hours > 14: hours -= 24
print("Etc/GMT" + ("-" if hours >= 0 else "+") + str(abs(hours)))')

rm -rf "$RAW" && mkdir -p "$RAW" "$FRAMED"
TZ=$PINNED_TZ build/DerivedData/Build/Products/Debug/NZTransportPlanner.app/Contents/MacOS/NZTransportPlanner \
    -uiScreenshots "$PWD/$RAW" -AppleLocale en_NZ -AppleLanguages "(en-NZ)" -AppleICUForce24HourTime NO
echo "Rendered $(ls "$RAW" | wc -l | tr -d ' ') screens into $RAW"

STAGE=build/frame && rm -rf "$STAGE" && mkdir -p "$STAGE"
python3 - "$STAGE" <<'PY'
import json, pathlib, sys
stage = pathlib.Path(sys.argv[1])
m = json.loads(pathlib.Path("screenshots/manifest.json").read_text())
template = pathlib.Path(m["template"]).read_text()
for s in m["screens"]:
    page = stage / s["id"]
    page.mkdir()
    html = (template.replace("{{BG1}}", m["bg1"]).replace("{{BG2}}", m["bg2"]).replace("{{TEXT}}", m["text"])
            .replace("{{FRAME_CLASS}}", m["frame"]).replace("{{HEADLINE}}", s["headline"])
            .replace("{{SUBHEADLINE}}", s["subheadline"]))
    (page / "index.html").write_text(html)
    (page / "shot.png").write_bytes(pathlib.Path(f"screenshots/raw/mac/{s['id']}.png").read_bytes())
    print(s["id"])
PY
for id in $(ls "$STAGE"); do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=2880,1800 \
        --screenshot="$PWD/$FRAMED/$id.png" "file://$PWD/$STAGE/$id/index.html" >/dev/null 2>&1
done
echo "Framed $(ls "$FRAMED" | wc -l | tr -d ' ') App Store screens into $FRAMED"
