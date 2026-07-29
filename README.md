# Decent Timer

A big, glanceable **counter-top timer app for iPad** — two count-up and two count-down
timers on one screen, plus a full-screen clock/screensaver for when it's idle. Made for the
kitchen counter: large numbers, large buttons, and it never sleeps.

Objective-C, **programmatic UIKit (no storyboards)**. One source tree, **two build targets**:

| Target | Device | Arch | Distribution |
|--------|--------|------|--------------|
| **iOS 9 / 32-bit** | original iPad mini 1 (`iPad2,5`, iOS 9.3.5) | armv7 | jailbreak sideload |
| **Modern** | any current iPad, + Mac Catalyst | arm64 | App Store / sideload (AltStore etc.) |

The modern-only scene lifecycle is `#if`-guarded so the very same `.m`/`.h` files compile for
both.

## Features

- **Live clock** at the top (`H:mm`) with the weekday under it. Auto-shrinks to fit.
- **Four timers on one screen** — two count **up**, two count **down**.
  - While running, a count-up shows *"Started at H:mm"*; a count-down shows
    *"Started at H:mm, ETA H:mm"* (ETA recomputed every tick).
  - Values read `MM:SS`, rolling to `H:MM:SS` past an hour. Grey when idle, white when
    running, orange in overtime.
- **Set a duration two ways:** tap **– / +** (press and hold to change fast), or **tap a timer
  to type it** on a full-screen keypad. The keypad is smart — enter `1.5h`, `90s`, `1:30`, or
  just `5`.
- **Overtime:** count-downs keep going past zero, the screen gently pulses, and it re-dings
  every few seconds so you know how long ago it finished.
- **Screensaver:** after a while idle (or on demand) it switches to a full-screen clock with
  the Decent Espresso logo, drifting slightly to avoid burn-in — so it doubles as a
  counter-top clock. Never activates while a timer is running.
- Portrait and landscape. No accounts, no ads, no tracking, **no network access at all.**

## Repository layout

```
KitchenTimer/            Source (main.m, AppDelegate.m, ViewController.m — all UI logic)
  App-Info.plist         Info.plist for the modern build (generated into the app by XcodeGen)
  Assets.xcassets/       Modern app icon
project.yml              XcodeGen spec for the modern Xcode project
build-armv7.sh           Cross-compiles the 32-bit iOS 9 build (see below)
simrun.sh                Builds + runs the modern build in the iOS Simulator
store/                   App Store listing copy, privacy policy, submission checklist
```

## Building — modern iPad (arm64)

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate                 # project.yml -> KitchenTimer.xcodeproj
open KitchenTimer.xcodeproj       # pick your team under Signing & Capabilities, then Run
```

- **Simulator iteration:** `./simrun.sh` builds the shared source for the iOS Simulator and
  launches it on an iPad mini simulator.
- **Mac Catalyst:** the target has `SUPPORTS_MACCATALYST = YES`; build with the *My Mac
  (Mac Catalyst)* destination.
- **Sideload `.ipa`:** for an unsigned device build to hand to a sideloader (AltStore and
  friends re-sign on install):

  ```bash
  xcodebuild -project KitchenTimer.xcodeproj -scheme KitchenTimer -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  # then: mkdir Payload && cp -R <built>/KitchenTimer.app Payload/ && zip -qry DecentTimer.ipa Payload
  ```

  There are no nested frameworks or dylibs — it's a single small executable — so on-device
  re-signing is trouble-free.

## Building — original iPad mini 1 (32-bit armv7, iOS 9)

Modern Xcode dropped armv7 and won't target iOS 9, and Apple-Silicon Macs can't run an old
Xcode. `build-armv7.sh` sidesteps that by cross-compiling directly with `clang` against an
old iOS SDK:

- Needs the **theos `iPhoneOS9.3.sdk`** (`~/theos/sdks/iPhoneOS9.3.sdk`) and **`ldid`**
  (`brew install ldid`).
- The script forces the classic linker (`-ld_classic`) and synthesizes a couple of stubs the
  theos SDK is missing, then `ldid`-signs the result with the entitlements a jailbroken device
  needs to launch a self-signed app.

```bash
./build-armv7.sh                  # -> .build-armv7/KitchenTimer.app  (armv7, ldid-signed)
```

Install it on a jailbroken iPad mini 1 by copying the built `.app` into `/Applications/`,
`chmod -R 755`, then `uicache -p /Applications/KitchenTimer.app` and respring.

## Privacy

Decent Timer collects nothing and makes no network connections — everything runs on-device.
See [`store/privacy.md`](store/privacy.md).
