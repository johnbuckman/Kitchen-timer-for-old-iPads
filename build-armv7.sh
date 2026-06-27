#!/bin/bash
# Build a 32-bit (armv7) iOS 9 KitchenTimer.app on a modern Mac, ready to drop onto
# a JAILBROKEN iPad mini 1 (iOS 9.3.5). Produces .build-armv7/KitchenTimer.app, ldid-signed.
#
# Requires: theos iPhoneOS9.3 SDK at $SDK below, ldid (brew install ldid).
# The modern Xcode linker can't normally link this old SDK, so we:
#   - force the classic linker (-ld_classic)
#   - synthesize two stubs the theos SDK is missing (liblaunch + basic mem funcs)
set -e

SDK="${SDK:-$HOME/theos/sdks/iPhoneOS9.3.sdk}"
SRC="$(cd "$(dirname "$0")/KitchenTimer" && pwd)"
OUT="$(dirname "$0")/.build-armv7"
APP="$OUT/KitchenTimer.app"
BUNDLE_ID="com.johnbuckman.KitchenTimer"

[ -d "$SDK" ] || { echo "ERROR: iOS 9.3 SDK not found at $SDK"; exit 1; }

# --- Idempotent SDK fixups -------------------------------------------------
# 1) libSystem re-exports liblaunch but the SDK omits its stub.
if [ ! -f "$SDK/usr/lib/system/liblaunch.tbd" ]; then
  cat > "$SDK/usr/lib/system/liblaunch.tbd" <<'TBD'
---
archs:                 [ armv7, armv7s, arm64, i386, x86_64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       0
compatibility-version: 1
exports:
  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]
    symbols:            [ _bootstrap_port, _bootstrap_look_up, _launch_msg,
                          _launch_data_free, _launch_data_new_string ]
...
TBD
  echo "patched SDK: added liblaunch.tbd"
fi
# 2) libsystem_c stub is missing the basic mem functions the compiler emits.
if ! grep -q '\[ _memset,' "$SDK/usr/lib/system/libsystem_c.tbd"; then
  python3 - "$SDK/usr/lib/system/libsystem_c.tbd" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
add=("  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]\n"
     "    symbols:            [ _memset, _memcpy, _memmove, _memcmp, _memchr, _bzero ]\n")
s=s.replace("exports:\n","exports:\n"+add,1)
open(p,'w').write(s)
PY
  echo "patched SDK: added mem symbols to libsystem_c.tbd"
fi

# --- Compile + link (armv7, iOS 9.0 deployment target) ----------------------
rm -rf "$OUT"; mkdir -p "$APP"
xcrun clang -arch armv7 -isysroot "$SDK" -miphoneos-version-min=9.0 -fobjc-arc \
  -Wl,-ld_classic \
  -framework UIKit -framework Foundation -framework AudioToolbox \
  "$SRC/main.m" "$SRC/AppDelegate.m" "$SRC/ViewController.m" \
  -o "$APP/KitchenTimer" 2>&1 | grep -viE "tbd file|iOS Simulator|-ld_classic is deprecated" || true

file "$APP/KitchenTimer" | grep -q arm_v7 || { echo "ERROR: did not produce an armv7 binary"; exit 1; }

# --- Bundle Info.plist (literal values; armv7 capability) -------------------
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>KitchenTimer</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>KitchenTimer</string>
  <key>CFBundleDisplayName</key><string>Kitchen Timer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>9.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>DTPlatformName</key><string>iphoneos</string>
  <key>DTPlatformVersion</key><string>9.3</string>
  <key>DTSDKName</key><string>iphoneos9.3</string>
  <key>UIDeviceFamily</key><array><integer>2</integer></array>
  <key>UIRequiredDeviceCapabilities</key><array><string>armv7</string></array>
  <key>CFBundleIconFiles</key><array><string>Icon-76.png</string><string>Icon-76@2x.png</string></array>
  <key>CFBundleIcons~ipad</key>
  <dict><key>CFBundlePrimaryIcon</key><dict>
    <key>CFBundleIconFiles</key><array><string>Icon-76</string></array>
  </dict></dict>
  <key>UIStatusBarHidden</key><true/>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict></plist>
PLIST

# --- App icon (so it's identifiable on the home screen) --------------------
cp "$SRC/Icon-76.png" "$SRC/Icon-76@2x.png" "$APP/" 2>/dev/null || echo "(no icon PNGs found - skipping)"

# --- Pseudo-sign for a jailbroken device -----------------------------------
ldid -S "$APP/KitchenTimer"

echo "BUILT + SIGNED: $APP"
file "$APP/KitchenTimer"
ldid -e "$APP/KitchenTimer" >/dev/null 2>&1 && echo "(signed)"
