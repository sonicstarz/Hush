#!/bin/zsh
# Builds Hush.app and installs it to /Applications.
set -e
cd "$(dirname "$0")"
APP=build/Hush.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o $APP/Contents/MacOS/Hush
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Hush</string>
  <key>CFBundleIdentifier</key><string>com.calebarzie.hush</string>
  <key>CFBundleExecutable</key><string>Hush</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign "Apple Development" $APP 2>/dev/null || codesign --force --sign - $APP
pkill -x Hush || true
rm -rf /Applications/Hush.app && cp -R $APP /Applications/
echo "Installed /Applications/Hush.app"
