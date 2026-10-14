#!/bin/zsh
# Zips build/Tsuta.app for a GitHub release: build/Tsuta-<version>-macos.zip
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "$@"
ZIP="build/Tsuta-$(<VERSION)-macos.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Tsuta.app "$ZIP"
shasum -a 256 "$ZIP"
echo "OK → $ZIP"
