# Decent Timer — App Store submission checklist

Everything in the repo is ready (iOS 15 target, name "Decent Timer", bundle id
`com.decentespresso.kitchentimer`, team `XLS3XF57J8`, app icon, screenshots, listing copy).
The steps below are the ones that must happen interactively in Xcode / App Store Connect
under the Decent Espresso account.

## 0. One-time, in Xcode (Settings → Accounts)
- Make sure the **Decent Espresso (Vid Tadel) Apple ID** is signed in, with the
  **XLS3XF57J8** team available. The project already sets that team + automatic signing.

## 1. Create the app record — App Store Connect (appstoreconnect.apple.com)
- My Apps → ➕ → New App
  - Platform: iOS
  - Name: **Decent Timer**  (fallback: "Decent Kitchen Timer" if taken)
  - Primary language: English (U.S.)
  - Bundle ID: **com.decentespresso.kitchentimer**
    - If it's not in the dropdown, register it first at developer.apple.com →
      Certificates, IDs & Profiles → Identifiers → ➕ (App ID, explicit, that bundle id).
      (Xcode also auto-registers it on first Archive.)
  - SKU: anything unique, e.g. `decent-timer-001`

## 2. Fill the product page (paste from store/listing.md)
- Name, Subtitle, Promotional text, Description, Keywords, Support/Marketing/Privacy URLs.
- Category: Utilities.
- Age rating questionnaire → all "None" → 4+.
- **Screenshots**: upload the four PNGs in `store/screenshots/` (they're 2064×2752, the
  13-inch iPad size App Store wants). Order: 01-main, 02-running, 03-keypad, 04-screensaver.

## 3. App Privacy (see store/privacy.md)
- "Data collected?" → **No** → Data Not Collected.
- Add the **Privacy Policy URL** (host the text from store/privacy.md).

## 4. Build & upload — Xcode
- Open `KitchenTimer.xcodeproj`.
- Set the run destination to **Any iOS Device (arm64)**.
- Bump version/build if needed (currently 1.0 / 1).
- Product → **Archive**.
- In the Organizer: **Distribute App → App Store Connect → Upload** (let Xcode manage signing).
- Wait for the build to finish processing in App Store Connect (a few minutes to ~1 hr).

## 5. Submit
- Back in App Store Connect, on the version: select the processed **Build**.
- (Recommended) push to **TestFlight** first and install on your own iPad to sanity-check.
- Answer Export Compliance (no encryption → "No").
- **Add for Review → Submit**. Review is typically 1–3 days.

## Heads-ups
- **Minimum functionality (Guideline 4.2):** a simple timer can get flagged as too simple.
  The keypad entry, overtime alarm, "started at / ETA" labels, and the screensaver clock all
  help argue it's a complete utility. If rejected, reply explaining the feature set.
- This App Store build is **separate** from the iOS 9 jailbreak build (`build-armv7.sh`),
  which keeps bundle id `com.johnbuckman.KitchenTimer`. They share the same source.
- The app icon (`KitchenTimer/Assets.xcassets/AppIcon.appiconset/icon_1024.png`) is a generated
  stopwatch — swap in your preferred SVG-derived 1024 PNG anytime before submitting.
