# Kitchen Timer — 32-bit iOS 9 iPad app

A counter-top kitchen timer for the **original iPad mini (1st gen, 2012, A1432/A1454/A1455)**,
the only 32-bit iPad mini — it tops out at **iOS 9.3.5**.

## What it does
- **Live clock** at the top (HH:MM:SS), and the screen never sleeps.
- **3 stopwatches** — count UP in whole minutes. Each: Start/Stop + Reset.
- **3 countdown timers** — set in whole minutes with – / +, then Start/Stop + Reset.
  When one hits 0 it plays the system alert tone, turns orange, and shows an alert.

No hours, no seconds anywhere — minute granularity only, as requested.
Objective-C, programmatic UIKit (no storyboards) for maximum old-Xcode robustness.

## Build requirements (the hard part — see notes)
A 32-bit armv7 binary for iOS 9 can ONLY be produced by **Xcode ≤ 10.3 on macOS ≤ 10.14
(Mojave)**. Xcode 11+ and every cloud CI (GitHub Actions, AWS EC2 Mac, MacStadium) dropped
armv7. Apple-Silicon Macs cannot run a Mojave VM. So you need either:

1. **An old Mac running Mojave + Xcode 10.1** (recommended). A free Apple ID signs and
   sideloads it straight to the iPad.
2. **theos** on a modern Mac (cross-compiles armv7 with a bundled iOS 9 SDK) — cleanest if
   the mini is jailbroken (iPad mini 1 / 9.3.5 → Phoenix jailbreak).

## To build in Xcode 10.1 (path 1)
1. Copy this `KitchenTimer` folder to the old Mac.
2. Open `KitchenTimer.xcodeproj`.
3. Select your team under Signing & Capabilities (change the bundle id
   `com.johnbuckman.KitchenTimer` if Xcode complains it's taken).
4. Plug in the iPad mini, pick it as the run destination, press Run.

The project is preset to: Deployment Target **iOS 9.0**, `ARCHS = armv7`,
`VALID_ARCHS = armv7`, `TARGETED_DEVICE_FAMILY = 2` (iPad), `ONLY_ACTIVE_ARCH = NO`.

## Files
- `KitchenTimer/main.m` — entry point
- `KitchenTimer/AppDelegate.{h,m}` — window setup, keeps screen awake
- `KitchenTimer/ViewController.{h,m}` — all UI + timer logic
- `KitchenTimer/Info.plist` — armv7 capability, iPad orientations
- `KitchenTimer.xcodeproj` — Xcode-10-compatible project
