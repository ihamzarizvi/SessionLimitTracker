#!/usr/bin/env bash
# Builds Session Limit Tracker.app and packages it into a distributable .dmg.
# Needs only the Swift toolchain + Command Line Tools — no full Xcode required.
#
#   ./Scripts/build-dmg.sh
#
# Signing:
#   default            ad-hoc signature (works locally; Gatekeeper will warn on
#                      other Macs because it is not notarised)
#   SIGN_IDENTITY=...  sign with a "Developer ID Application: ..." identity and
#                      enable the hardened runtime, ready for notarisation:
#
#     SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-dmg.sh
#     xcrun notarytool submit dist/SessionLimitTracker-*.dmg \
#       --apple-id you@example.com --team-id TEAMID --password app-specific-pw --wait
#     xcrun stapler staple dist/SessionLimitTracker-*.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
NAME="SessionLimitTracker"
DISPLAY="Session Limit Tracker"
BUNDLE_ID="com.hamzarizvi.SessionLimitTracker"
VERSION="${VERSION:-1.0.0}"
MIN_MACOS="14.0"

DIST="$ROOT/dist"
APP="$DIST/$DISPLAY.app"
DMG="$DIST/$NAME-$VERSION.dmg"

echo "==> Building release binary"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$NAME"
[ -x "$BIN" ] || { echo "binary not found at $BIN"; exit 1; }

echo "==> Assembling app bundle"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"

echo "==> Rendering icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$DISPLAY</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Hamza Rizvi</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --timestamp --options runtime \
             --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP"
    echo "    (ad-hoc — not notarised; other Macs will show a Gatekeeper warning)"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Building DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DISPLAY" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "App: $APP"
echo "DMG: $DMG  ($(du -h "$DMG" | cut -f1))"
