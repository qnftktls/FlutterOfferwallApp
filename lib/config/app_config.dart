/// Single source of truth for every ad unit id used by the app.
///
/// ⚠️ REPLACE THESE WITH YOUR REAL ADMOB IDs before a production release.
/// The constants below are Google's OFFICIAL TEST ids. They always fill and are
/// safe to ship in a debug build, but they earn NOTHING.
///
/// Where to get yours: https://admob.google.com -> Apps -> Ad units.
class AdIds {
  AdIds._();

  /// Bottom home banner — Google official test id. REPLACE before release.
  static const String bannerHome = 'ca-app-pub-3940256099942544/6300978111';

  /// Offer detail interstitial — Google official test id. REPLACE before release.
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

/// Offerwall provider configuration.
///
/// Freecash-style apps aggregate offers from a provider (or several). To go
/// live you only edit this file: set [provider], your publisher [appId] and
/// [userId], and the URL + allowed hosts are derived automatically.
enum OfferwallProvider {
  /// Bundled placeholder page (no account needed).
  placeholder,

  /// URL/iframe style providers.
  ayet,
  adgem,
  tapjoy,
  notik,
  lootably,
}

class OfferwallConfig {
  OfferwallConfig._();

  /// The active provider. Switch to `ayet`, `adgem`, … once you have an account.
  static const OfferwallProvider provider = OfferwallProvider.placeholder;

  /// Your publisher/app id from the provider dashboard.
  static const String appId = '';

  /// A stable per-user id (hash of your user id). Never PII.
  static const String userId = 'demo-user';

  /// Optional server-signed token appended to the URL (anti-fraud).
  static const String signature = '';

  /// The JS object name the offerwall page uses to call back into native code.
  static const String bridgeName = 'AndroidOfferwall';

  /// Explicit provider URL override. Leave blank to build from [provider].
  static const String explicitUrl = '';

  /// Extra hosts to allow inside the WebView (beyond the resolved URL host).
  static const List<String> extraAllowedHosts = <String>[];

  /// Resolves the offerwall URL for the active provider.
  static String get offerwallUrl {
    if (explicitUrl.trim().isNotEmpty) return explicitUrl.trim();
    switch (provider) {
      case OfferwallProvider.placeholder:
        return '';
      case OfferwallProvider.ayet:
        return 'https://web.ayet.io/publisher?app_id=$appId&user_id=$userId';
      case OfferwallProvider.adgem:
        return 'https://api.adgem.com/v1/wall?appid=$appId&playerid=$userId';
      case OfferwallProvider.tapjoy:
        return 'https://offerwall.tapjoy.com/?publisher_user_id=$userId'
            '&pub_id=$appId';
      case OfferwallProvider.notik:
        return 'https://notik.me/offers?app_id=$appId&user_id=$userId';
      case OfferwallProvider.lootably:
        return 'https://wall.lootably.com/?placement_id=$appId&user_id=$userId';
    }
  }

  /// Hosts allowed to run INSIDE the WebView; everything else opens externally.
  static Set<String> get allowedHosts {
    final Set<String> hosts = <String>{...extraAllowedHosts};
    final Uri? uri = Uri.tryParse(offerwallUrl);
    if (uri != null && uri.host.isNotEmpty) hosts.add(uri.host);
    return hosts;
  }

  /// Whether we're running the bundled placeholder (no remote URL).
  static bool get isPlaceholder => offerwallUrl.trim().isEmpty;
}

/// Payout / cashout configuration.
class PayoutConfig {
  PayoutConfig._();

  /// Minimum USD that can be withdrawn across any method (provider minimums can
  /// be higher; see the per-option `minCash`).
  static const double globalMinCash = 5.0;

  /// Base URL of your backend that fulfills payouts. In production the app POSTs
  /// a withdrawal request here and the server talks to the payout provider.
  /// Leave blank to use the `requestPayout` Cloud Function instead.
  static const String backendBaseUrl = '';

  /// When true, cashout is simulated locally (demo). Set false once
  /// [backendBaseUrl] is wired to a real service.
  static const bool demoMode = true;
}

/// Anti-fraud / server-verification configuration.
class SecurityConfig {
  SecurityConfig._();

  /// When `true`, rewards and payouts go through Cloud Functions
  /// (`claimOffer` / `requestPayout`) so the **server** is the source of truth.
  ///
  /// Requires the `functions/` folder to be deployed (Blaze plan). If the
  /// callables are unreachable the app falls back to the local demo path and
  /// shows the sync state as "offline", so nothing crashes.
  ///
  /// ⚠️ Set this to `true` for any build where real money is involved.
  static const bool useServerVerification = true;

  /// Firestore collection holding payout requests (written by the server).
  static const String payoutsCollection = 'payouts';

  /// Name of the offerwall postback secret (server-side only — never in the app).
  static const String offerwallSecretName = 'OFFERWALL_SECRET';
}
