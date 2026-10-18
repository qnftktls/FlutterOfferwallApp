/// No-op interstitial manager for Flutter Web (where `google_mobile_ads` is
/// unavailable). Mirrors the API of the native implementation.
class InterstitialAdManager {
  InterstitialAdManager._();
  static final InterstitialAdManager instance = InterstitialAdManager._();

  void preload() {}

  bool showIfAvailable() => false;
}
