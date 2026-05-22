#!/usr/bin/env bash
# Generate all required iOS icon sizes from a single 1024x1024 source PNG.
# Usage:  ./scripts/generate-icons.sh path/to/source-1024.png
# Requires sips (preinstalled on macOS).

set -euo pipefail

SRC="${1:-FireworksChat/Assets.xcassets/AppIcon.appiconset/icon_1024.png}"
DEST_DIR="FireworksChat/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SRC" ]; then
  echo "Source icon not found: $SRC"
  exit 1
fi

mkdir -p "$DEST_DIR"

# Required sizes in pixels (matching filenames already referenced).
declare -a SIZES=(20 29 40 58 60 76 80 87 120 152 167 180)

for s in "${SIZES[@]}"; do
  out="$DEST_DIR/icon_${s}.png"
  sips -z "$s" "$s" "$SRC" --out "$out" >/dev/null
  echo "Generated $out"
done

# Ensure 1024 exists at destination (skip if source is already there).
DEST_1024="$DEST_DIR/icon_1024.png"
if [ "$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" != "$(cd "$(dirname "$DEST_1024")" && pwd)/$(basename "$DEST_1024")" ]; then
  cp -f "$SRC" "$DEST_1024"
  echo "Copied source to $DEST_1024"
else
  echo "Source is already at $DEST_1024, skipping copy"
fi
