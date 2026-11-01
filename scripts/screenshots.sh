#!/bin/zsh
# Re-captures every tour screen (admin S*, tracker T*) in Light and Dark into Docs/screenshots/{light,dark}.
# Usage: scripts/screenshots.sh [simulator-udid]   (defaults to the first booted simulator)
set -e
cd "$(dirname "$0")/.."
U=${1:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)}
[ -n "$U" ] || { echo "No booted simulator"; exit 1; }
capture() {  # scheme, only-testing, mode
  local bundle=$(mktemp -d)/tour.xcresult out=$(mktemp -d)
  xcodebuild -project Rentro.xcodeproj -scheme "$1" -destination "id=$U" -derivedDataPath build \
    test -only-testing:"$2" -resultBundlePath "$bundle" > /dev/null
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$out" > /dev/null
  mkdir -p Docs/screenshots/$3
  python3 - "$out" Docs/screenshots/$3 <<'PY'
import json, shutil, sys, re
src, dst = sys.argv[1:3]
for e in json.load(open(f"{src}/manifest.json")):
    for a in e["attachments"]:
        name = re.sub(r"_\d+_[0-9A-F-]{36}\.png$", ".png", a["suggestedHumanReadableName"])
        shutil.copy(f"{src}/{a['exportedFileName']}", f"{dst}/{name}")
PY
}
for mode in light dark; do
  xcrun simctl ui "$U" appearance $mode
  capture RentroAdmin RentroUITests/ScreenshotTour $mode
  capture RentroTracker RentroTrackerUITests/TrackerScreenshotTour $mode
  echo "$mode: $(ls Docs/screenshots/$mode | wc -l) screens"
done
xcrun simctl ui "$U" appearance light
