/// Platform-conditional Ads SDK initializer.
///
/// - Android / iOS -> initializes `google_mobile_ads`
/// - Flutter Web   -> no-op
library;

export 'ads_init_io.dart' if (dart.library.js_interop) 'ads_init_web.dart';
