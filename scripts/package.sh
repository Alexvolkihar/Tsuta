#!/bin/zsh
# Zips build/Hanko.app for a GitHub release: build/Hanko-<version>-macos.zip
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "$@"
ZIP="build/Hanko-$(<VERSION)-macos.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Hanko.app "$ZIP"
shasum -a 256 "$ZIP"
echo "OK → $ZIP"
