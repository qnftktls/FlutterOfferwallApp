/// Platform-conditional offerwall surface.
///
/// - Android / iOS -> a real `webview_flutter` WebView (`offerwall_view_io.dart`)
/// - Flutter Web   -> a Flutter-rendered fallback (`offerwall_view_web.dart`)
///
/// Both expose the same `OfferwallView` widget and share bridge logic through
/// [OfferwallController], so the rest of the app is platform-agnostic.
library;

export 'offerwall_view_io.dart'
    if (dart.library.js_interop) 'offerwall_view_web.dart';
