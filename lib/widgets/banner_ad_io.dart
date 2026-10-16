import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';

/// A bottom-anchored AdMob banner (Android / iOS).
///
/// Loaded with [AdIds.bannerHome] — Google's official test id until you swap it.
/// Banner failures never break the app; we log and move on.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key, this.height = 50});

  /// Reserved height so the layout doesn't jump while the ad loads.
  final double height;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final BannerAd banner = BannerAd(
      adUnitId: AdIds.bannerHome,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) return;
          setState(() {
            _bannerAd = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          debugPrint('Banner failed to load: ${error.message}');
        },
      ),
    );
    banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _bannerAd == null) {
      return SizedBox(height: widget.height);
    }
    return SizedBox(
      height: widget.height,
      width: _bannerAd!.size.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
