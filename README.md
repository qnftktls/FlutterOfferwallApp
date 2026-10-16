# Rewards Hub — Flutter (AdMob banner + WebView offerwall)

A hybrid monetization home screen built with **Flutter**, targeting **Android and iOS
from a single codebase** (with a Flutter Web preview). Ported 1:1 from the earlier
Android-native Kotlin build, keeping the same structure, palette, and JS bridge contract.

```
┌───────────────────────────────────────────┐
│  Rewards Hub                    1,250 pts  │  ← header (app name + live balance)
├───────────────────────────────────────────┤
│                                            │
│            OFFERWALL (WebView)             │  ← scrollable offer list
│            provider HTML + JS bridge       │
│                                            │
├───────────────────────────────────────────┤
│            AdMob BANNER (test id)          │  ← fixed bottom banner
└───────────────────────────────────────────┘
```

Runs out of the box with **Google's official test ad units** and a **bundled
placeholder offerwall page** — no accounts required to see it work. Swap in your
real IDs and provider URL following the checklist below.

---

## 1. Why Flutter

One Dart codebase → **Android + iOS** (and a web preview). The three-part layout
(header / WebView offerwall / bottom banner) maps cleanly onto Flutter widgets, and
the JS↔native bridge is implemented with `webview_flutter`'s `JavaScriptChannel`.

| Layer | Android / iOS | Flutter Web (preview) |
|-------|----------------|------------------------|
| Offerwall | real `webview_flutter` WebView | Flutter-rendered fallback list |
| Banner | real `google_mobile_ads` banner | same-height labelled placeholder |
| Balance | `shared_preferences` (persisted) | `shared_preferences` (localStorage) |

Platform selection uses **conditional imports** (`if (dart.library.js_interop)`) so
the app is platform-agnostic at the call site.

## 2. Project structure

```
flutter_app/
├── pubspec.yaml
├── assets/
│   └── offerwall/offerwall_placeholder.html   # demo offerwall (shows the bridge)
└── lib/
    ├── main.dart                              # app entry + provider wiring
    ├── config/
    │   └── app_config.dart                    # ⚠️ AdIds + OfferwallConfig live here
    ├── models/
    │   └── offer.dart                         # Offer + RewardTransaction
    ├── services/
    │   ├── points_repository.dart             # balance state (ChangeNotifier, persisted)
    │   ├── offerwall_controller.dart          # bridge logic (offerCompleted/ready/error)
    │   ├── offerwall_message.dart             # bridge payload parsing
    │   ├── ads_init.dart                      # conditional Ads SDK init
    │   ├── ads_init_io.dart / ads_init_web.dart
    ├── screens/
    │   └── home_screen.dart                   # header + offerwall + banner
    ├── theme/
    │   └── app_theme.dart                     # navy/mint tokens, Material 3, dark mode
    └── widgets/
        ├── rewards_header.dart                # app name + live balance pill
        ├── offerwall_view.dart                # conditional export
        ├── offerwall_view_io.dart             # real WebView (mobile)
        ├── offerwall_view_web.dart            # Flutter fallback (web)
        ├── banner_ad.dart                     # conditional export
        ├── banner_ad_io.dart                  # real AdMob banner (mobile)
        └── banner_ad_web.dart                 # labelled placeholder (web)
```

## 3. Build & run

**Requirements:** Flutter 3.35.x / Dart 3.9.x. For Android: JDK 17 + Android SDK 35.

```bash
flutter pub get

# Web preview
flutter run -d chrome
# or a production web build
flutter build web --release

# Android
flutter run -d android
flutter build apk --release

# iOS (on macOS)
flutter run -d ios
```

On first run you'll see the placeholder offerwall. Tap any offer card or the
"Simulate" button — the header balance updates via the bridge, proving the
WebView ↔ Dart path works end to end. On touch-and-hold the balance pill you can
reset points (useful for testing).

---

## 4. Architecture & data flow

```
Offerwall HTML  ──postMessage(JSON)──▶  JavaScriptChannel("AndroidOfferwall")
                                                │
                                  OfferwallController.handleMessage()
                                                │
                                   PointsRepository.addPoints(pts)
                                                │
                        ChangeNotifier ──▶ header balance + snack bar
```

**Header** — `RewardsHeader` observes `PointsRepository.points` and formats it with
tabular figures. Replace the repository with Room/DataStore-equivalent or your
backend API without touching the UI.

**Center** — the WebView loads either the bundled placeholder
(`assets/offerwall/…`) or your provider URL (`OfferwallConfig.offerwallUrl`). Only
hosts in `OfferwallConfig.allowedHosts` stay inside the app; every other link is
blocked (the JS bridge is exposed to whatever page loads).

**Bottom** — a banner loaded with `AdIds.bannerHome`.

### JS ↔ native bridge contract

The bridge keeps the **same contract** the native Kotlin build used, so provider
pages written for it work unchanged:

| Direction | Call | Meaning |
|-----------|------|---------|
| JS → native | `window.AndroidOfferwall.postMessage('{"type":"offerCompleted","offerId":"..","reward":250,"signature":".."}')` | Credit reward for a finished offer |
| JS → native | `…postMessage('{"type":"offerwallReady"}')` | Page is interactive; native pushes the current balance |
| JS → native | `…postMessage('{"type":"offerwallError","reason":".."}')` | Report a fatal offerwall error |
| native → JS | `window.dispatchEvent(new CustomEvent('nativeBalance', {detail: n}))` | Push balance into the page |

The bundled `offerwall_placeholder.html` demonstrates all four calls. Point your
provider's page (or your own wrapper page) at the same object to go live.

---

## 5. Checklist — replace before a production release

- [ ] **1. Package / bundle id.** Currently `com.rewardshub.rewards`
  (`android/app/build.gradle.kts` `applicationId`/`namespace`, iOS bundle id).
- [ ] **2. AdMob App ID.**
  - Android: `android/app/src/main/AndroidManifest.xml` →
    `com.google.android.gms.ads.APPLICATION_ID` meta-data.
  - iOS: `ios/Runner/Info.plist` → `GADApplicationIdentifier`.
  - Format `ca-app-pub-…~…`.
- [ ] **3. Ad unit IDs.** `lib/config/app_config.dart` → `AdIds.bannerHome`,
  `interstitialOfferDetail`, `rewardedBonus` (format `ca-app-pub-…/…`).
- [ ] **4. Turn off test-ads mode.** `AdIds.useTestAds = false`.
- [ ] **5. Offerwall provider.** Get a publisher account + app ID from your chosen
  provider (Tapjoy / adjoe / Ayet / AdGem / …). Then set
  `OfferwallConfig.offerwallUrl` and add the provider's host to
  `OfferwallConfig.allowedHosts`. SDK-based providers need their SDK + a button.
- [ ] **6. Server-side reward verification.** Never credit points from the client in
  production. Wire provider postbacks → your backend → a signed event the app
  consumes (`OfferwallController.handleMessage` marks exactly where to verify).
- [ ] **7. Privacy & compliance.** Privacy policy link, EEA/UK consent (Google UMP /
  GDPR), COPPA/age gate if relevant, and ATT disclosure on iOS.
- [ ] **8. Branding.** App name, palette in `lib/theme/app_theme.dart`, and launcher
  icons (already generated).

## 6. Extending to the next screens

The structure is ready for these additions:

**Offer detail screen** — add `OfferDetailScreen`, pass the offer id through the
bridge (extend the payload with `openOfferDetail`), and deep-link with
`Navigator`. Use `AdIds.interstitialOfferDetail` for a full-screen ad (respect
frequency caps).

**Reward history screen** — `PointsRepository.transactions` already keeps
`RewardTransaction`s; render them in a `ListView` (title, points, date, status).
Because the balance flows through a single notifier, both screens stay consistent
automatically.

## 7. Assumptions & limitations

1. **Flutter (Dart)** is the single codebase for Android + iOS; a web fallback is
   provided for preview only.
2. The offerwall is a **WebView placeholder** on mobile; real provider integration
   needs your publisher account and (for some providers) their SDK.
3. Rewards are **credited locally** to demonstrate the bridge — production requires
   server-side verification (checklist step 6).
4. AdMob uses **official test IDs**, so no revenue is generated until you replace them.
5. Dark/light theme follows the system setting automatically; the placeholder HTML
   adapts via `prefers-color-scheme`.
6. Accessibility baseline: ≥48dp touch targets, semantics labels, scalable text,
   high-contrast palette.
