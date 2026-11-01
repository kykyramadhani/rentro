#!/bin/zsh
# Re-extracts every localisable string from the last build into each app's Localizable.xcstrings.
# Usage: scripts/sync_strings.sh   (build the Rentro scheme first; new keys arrive untranslated, stale ones are marked)
set -e
cd "$(dirname "$0")/.."
for app in Rentro; do
  files=("${(@f)$(find build/Build/Intermediates.noindex -name '*.stringsdata' -path "*${app}.build*")}")
  [ ${#files[@]} -gt 0 ] || { echo "No .stringsdata for $app: build it first"; exit 1; }
  args=(); for f in $files; do args+=(--stringsdata "$f"); done
  xcrun xcstringstool sync "Apps/Rentro/Resources/Localizable.xcstrings" $args
  echo "$app: $(python3 -c "import json;print(len(json.load(open('Apps/Rentro/Resources/Localizable.xcstrings'))['strings']))") keys"
done
