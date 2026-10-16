/// Platform-conditional AdMob banner.
///
/// - Android / iOS -> a real `google_mobile_ads` banner (`banner_ad_io.dart`)
/// - Flutter Web   -> a same-height labelled placeholder (`banner_ad_web.dart`)
library;

export 'banner_ad_io.dart' if (dart.library.js_interop) 'banner_ad_web.dart';
