#!/bin/zsh
# Builds BusyMac.app and installs it to ~/Applications. No Xcode or App Store needed.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/BusyMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BusyMac "$APP/Contents/MacOS/BusyMac"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.busybar.busymac</string>
    <key>CFBundleName</key><string>BusyMac</string>
    <key>CFBundleExecutable</key><string>BusyMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Menu-bar only: no Dock icon. -->
    <key>LSUIElement</key><true/>
    <!-- The bar speaks plain HTTP on the local network. -->
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>BusyMac talks to your BUSY Bar on your local network.</string>
    <key>NSBonjourServices</key><array><string>_http._tcp</string></array>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for your own Mac, no developer account involved.
codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/BusyMac.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/BusyMac.app"
