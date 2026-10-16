import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';

/// Initializes the Google Mobile Ads SDK once, off the main thread (Android / iOS).
Future<void> initAds() async {
  if (AdIds.useTestAds && kDebugMode) {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: const <String>[]),
    );
  }
  // Initialize on a background isolate so the first frame is not blocked.
  await MobileAds.instance.initialize();
}
