import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';

/// Loads and shows a full-screen interstitial ad (Android / iOS only).
///
/// Freecash-style apps show an interstitial when opening an offer detail. Kept
/// intentionally simple: pre-load, show once, then reload.
class InterstitialAdManager {
  InterstitialAdManager._();
  static final InterstitialAdManager instance = InterstitialAdManager._();

  InterstitialAd? _ad;
  bool _loading = false;

  /// Pre-loads an interstitial so it is ready to show instantly.
  void preload() {
    if (_ad != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitialOfferDetail,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _ad = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _ad = null;
              preload();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError e) {
              ad.dispose();
              _ad = null;
              preload();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loading = false;
          if (kDebugMode) debugPrint('Interstitial failed: ${error.message}');
        },
      ),
    );
  }

  /// Shows the interstitial if one is ready. Returns `true` when shown.
  bool showIfAvailable() {
    final InterstitialAd? ad = _ad;
    if (ad == null) {
      preload();
      return false;
    }
    _ad = null;
    ad.show();
    return true;
  }
}
