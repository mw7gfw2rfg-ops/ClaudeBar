#!/bin/bash
# Assembles ClaudeBar.app from the SwiftPM product.
#
# There's no .xcodeproj on purpose: SwiftPM builds the binary, and an .app bundle is just
# a directory with an Info.plist in it. Generating an Xcode project to produce three files
# and a plist would be machinery nobody asked for.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/ClaudeBar.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeBar"
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>ClaudeBar</string>
    <key>CFBundleDisplayName</key>           <string>ClaudeBar</string>
    <key>CFBundleIdentifier</key>            <string>com.archierichardson.claudebar</string>
    <key>CFBundleExecutable</key>            <string>ClaudeBar</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>26.0</string>
    <!-- No Dock icon, no Cmd-Tab entry. This app lives in the menu bar only. -->
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for local use; a Developer ID signature is what would unlock
# UNUserNotificationCenter and SMAppService (see ISA § Decisions).
codesign --force --sign - "$APP" 2>/dev/null || echo "    (ad-hoc signing skipped)"

echo "==> built $APP"
