/// Platform-conditional interstitial ad manager.
///
/// - Android / iOS -> real `google_mobile_ads` interstitial
/// - Flutter Web   -> no-op
library;

export 'interstitial_io.dart'
    if (dart.library.js_interop) 'interstitial_web.dart';
