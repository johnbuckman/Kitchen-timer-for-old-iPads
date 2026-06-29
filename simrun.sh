#!/bin/bash
# Build the shared source for the iOS Simulator and run it on an iPad mini sim.
# This is the DESIGN-ITERATION track (modern iOS, arm64). It does NOT produce the
# 32-bit armv7 build for the real iPad mini 1 — use Xcode 10 / theos for that.
# The .m/.h files are identical across both tracks.
set -e

UDID="${SIM_UDID:-$(xcrun simctl list devices available | grep 'iPad mini' | head -1 | grep -oE '[0-9A-F-]{36}')}"
SRC="$(cd "$(dirname "$0")/KitchenTimer" && pwd)"
WORK="$(dirname "$0")/.simbuild"
APP="$WORK/KitchenTimer.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
BUNDLE=com.johnbuckman.KitchenTimer

rm -rf "$WORK"; mkdir -p "$APP"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>KitchenTimer</string>
  <key>CFBundleIdentifier</key><string>com.johnbuckman.KitchenTimer</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>KitchenTimer</string>
  <key>CFBundleDisplayName</key><string>Decent Timer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>12.0</string>
  <key>UIDeviceFamily</key><array><integer>2</integer></array>
  <key>UIStatusBarHidden</key><true/>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>Default</string>
          <key>UISceneDelegateClassName</key><string>SceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
</dict></plist>
PLIST

xcrun --sdk iphonesimulator clang \
  -arch arm64 -mios-simulator-version-min=12.0 -fobjc-arc -fmodules -isysroot "$SDK" \
  -framework UIKit -framework Foundation -framework AudioToolbox \
  "$SRC/main.m" "$SRC/AppDelegate.m" "$SRC/ViewController.m" \
  -o "$APP/KitchenTimer"

cp "$SRC/decent_logo.png" "$APP/" 2>/dev/null || echo "(no decent_logo.png - skipping)"

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE"
echo "Running $BUNDLE on $UDID"
