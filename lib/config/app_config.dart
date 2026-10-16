/// Single source of truth for every ad unit id used by the app.
///
/// Ported from the native project's `ads/AdIds.kt`.
///
/// ⚠️ REPLACE THESE WITH YOUR REAL ADMOB IDs before a production release.
/// The constants below are Google's OFFICIAL TEST ids. They always fill and are
/// safe to ship in a debug build, but they earn NOTHING.
///
/// Where to get yours: https://admob.google.com -> Apps -> Ad units.
///   - App ID         : looks like `ca-app-pub-################~##########` (tilde ~)
///   - Banner unit id : looks like `ca-app-pub-################/##########` (slash /)
///
/// The App ID is wired in Android (`android/app/src/main/AndroidManifest.xml`) and
/// iOS (`ios/Runner/Info.plist`). Banner ids are wired right here.
class AdIds {
  AdIds._();

  /// Bottom home banner — Google official test id. REPLACE before release.
  static const String bannerHome = 'ca-app-pub-3940256099942544/6300978111';

  /// Reserved for the next screens (offer detail). Google official test id.
  static const String interstitialOfferDetail =
      'ca-app-pub-3940256099942544/1033173712';

  /// Optional rewarded ad ("watch to double reward"). Google official test id.
  static const String rewardedBonus = 'ca-app-pub-3940256099942544/5224354917';

  /// Android AdMob App ID (Google official test id). Used in the manifest.
  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// iOS AdMob App ID (Google official test id). Used in Info.plist.
  static const String iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  /// While developing, keep this `true` so you never accidentally tap a live ad.
  static const bool useTestAds = true;
}

/// Offerwall configuration.
///
/// Ported from the native `MainActivity.offerwallUrl` + `allowedHosts`.
class OfferwallConfig {
  OfferwallConfig._();

  /// OFFERWALL URL.
  ///
  /// Leave BLANK to run the bundled placeholder page (`assets/offerwall/offerwall_placeholder.html`),
  /// which demonstrates the JS <-> Dart bridge with zero external dependencies.
  ///
  /// ⚠️ REPLACE with your provider's publisher URL once your offerwall account is approved.
  /// Most providers give you a URL like one of these (fill in YOUR app id / user id / signature):
  ///
  ///   Tapjoy : https://offerwall.tapjoy.com/?publisher_user_id=USER_ID&pub_id=APP_ID
  ///   Ayet   : https://web.ayet.io/...?app_id=APP_ID&user_id=USER_ID
  ///   AdGem  : https://api.adgem.com/v1/wall?appid=APP_ID&playerid=USER_ID
  ///   adjoe  : typically SDK-based (Playtime) — WebView path needs a provider-hosted web URL
  ///
  /// NOTE: provider accounts + keys are YOURS to obtain. No secrets belong in this file.
  static const String offerwallUrl = '';

  /// Hosts allowed to run INSIDE the WebView. Everything else opens in the system browser.
  ///
  /// Add your provider's host(s) here, e.g. "offerwall.tapjoy.com", "web.ayet.io", "api.adgem.com".
  /// The configured [offerwallUrl] host (if any) is matched automatically.
  static const List<String> allowedHosts = <String>[
    // 'offerwall.tapjoy.com',
    // 'web.ayet.io',
    // 'api.adgem.com',
  ];

  /// The JS object name the offerwall page uses to call back into native code.
  /// Matches the native app: `window.AndroidOfferwall.onOfferCompleted(...)`.
  static const String bridgeName = 'AndroidOfferwall';
}
