#!/bin/zsh
# Builds a release binary and wraps it into build/Tsuta.app (ad-hoc signed).
# Usage: scripts/build-app.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Tsuta"
VERSION="$(<VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARCHS=()
[[ "${1:-}" == "--universal" ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release --product "$NAME" "${ARCHS[@]}"
BIN="$(swift build -c release --show-bin-path "${ARCHS[@]}")/$NAME"

APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>dev.alexvolkihar.tsuta</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Alexvolkihar. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "OK → $APP ($VERSION, build $BUILD)"
