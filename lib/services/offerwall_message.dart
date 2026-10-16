import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The message contract exchanged between the offerwall page and Dart.
///
/// `type` is one of: `offerCompleted`, `offerwallReady`, `offerwallError`.
/// This mirrors the native app's `OfferwallBridge` JS interface.
class OfferwallMessage {
  const OfferwallMessage({
    required this.type,
    required this.offerId,
    required this.reward,
    required this.signature,
    required this.reason,
  });

  final String type;
  final String offerId;
  final int reward;
  final String signature;
  final String reason;

  bool get isOfferCompleted => type == 'offerCompleted';
  bool get isReady => type == 'offerwallReady';
  bool get isError => type == 'offerwallError';

  /// Parses a JSON payload posted by the offerwall page.
  static OfferwallMessage parse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      final Map<String, dynamic> map = decoded is Map
          ? decoded.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      return OfferwallMessage(
        type: (map['type'] ?? '').toString(),
        offerId: (map['offerId'] ?? map['offer_id'] ?? '').toString(),
        reward: _toInt(map['reward']),
        signature: (map['signature'] ?? '').toString(),
        reason: (map['reason'] ?? '').toString(),
      );
    } catch (_) {
      return OfferwallMessage(
        type: 'error',
        offerId: '',
        reward: 0,
        signature: '',
        reason: 'Malformed bridge payload: $raw',
      );
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// Whether the offerwall should render using a real WebView (native only).
///
/// `webview_flutter` has no web implementation, so on Flutter Web we render a
/// styled in-app fallback that exercises the same bridge logic for previews.
bool get supportsWebView => !kIsWeb;
