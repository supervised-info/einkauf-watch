#!/bin/sh
set -e
cd "$(dirname "$0")/.."
python3 Scripts/generate_icons.py
python3 Scripts/generate_xcodeproj.py
if command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen ist installiert — project.yml kann alternativ genutzt werden:"
  echo "  xcodegen generate"
fi
echo "Fertig: Einkauf.xcodeproj"
