import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../services/offerwall_message.dart';
import '../services/points_repository.dart';

/// Bridges the offerwall page and the rest of the app.
///
/// Ported from the native `web/OfferwallBridge.kt`. It receives messages posted
/// from the WebView's JS channel, credits rewards, and exposes feedback for the
/// UI (toast text, last error).
class OfferwallController extends ChangeNotifier {
  OfferwallController({PointsRepository? repository})
    : _repository = repository ?? PointsRepository.instance;

  final PointsRepository _repository;

  /// Set by the active offerwall surface so the controller can push the balance
  /// into the page when the offerwall signals it is ready.
  Future<void> Function(int balance)? onPushBalance;

  /// Last human-readable status (e.g. "You earned 250 points!").
  String? lastMessage;

  /// Non-null when the offerwall reported a fatal error.
  String? lastError;

  /// Handles a raw JSON payload posted from the offerwall page.
  ///
  /// Returns `true` when the message was understood.
  bool handleMessage(String raw) {
    final OfferwallMessage message = OfferwallMessage.parse(raw);

    if (message.isOfferCompleted) {
      // ⚠️ PRODUCTION NOTE: never trust the client for the reward amount.
      // Verify offer completion server-side (provider callback -> your backend ->
      // signed event) and only then credit. The direct credit below is for local
      // development only.
      final int newBalance = _repository.addPoints(
        message.reward,
        offerTitle: 'Offer ${message.offerId}',
      );
      lastMessage = 'You earned ${message.reward} points!';
      lastError = null;
      onPushBalance?.call(newBalance);
      if (kDebugMode) {
        debugPrint(
          'Offer completed: id=${message.offerId} reward=${message.reward} '
          'sig=${message.signature} balance=$newBalance',
        );
      }
      notifyListeners();
      return true;
    }

    if (message.isReady) {
      if (kDebugMode) {
        debugPrint('Offerwall ready');
      }
      onPushBalance?.call(_repository.points);
      return true;
    }

    if (message.isError) {
      lastError = message.reason.isEmpty ? 'Offerwall error' : message.reason;
      if (kDebugMode) {
        debugPrint('Offerwall error: $lastError');
      }
      notifyListeners();
      return true;
    }

    if (kDebugMode) {
      debugPrint('Unknown offerwall message: $raw');
    }
    return false;
  }

  /// The URL to load: the provider's, or the bundled placeholder page.
  String get resolvedUrl => OfferwallConfig.offerwallUrl.trim().isEmpty
      ? 'assets/offerwall/offerwall_placeholder.html'
      : OfferwallConfig.offerwallUrl;

  bool get isPlaceholder => OfferwallConfig.offerwallUrl.trim().isEmpty;

  /// Host set that may load inside the WebView; all other links open externally.
  Set<String> get allowedHosts {
    final Set<String> hosts = <String>{...OfferwallConfig.allowedHosts};
    final Uri? uri = Uri.tryParse(OfferwallConfig.offerwallUrl);
    if (uri != null && uri.host.isNotEmpty) {
      hosts.add(uri.host);
    }
    return hosts;
  }

  /// Whether [url] belongs to an allowed offerwall host.
  bool isInternalUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String host = uri?.host ?? '';
    if (host.isEmpty) return true; // asset: / data: / about: stay internal
    return allowedHosts.any((h) => host == h || host.endsWith('.$h'));
  }
}
