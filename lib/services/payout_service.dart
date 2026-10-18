import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/offer.dart';

/// Outcome of a payout request.
class PayoutResult {
  const PayoutResult({required this.ok, required this.message, this.txId});

  final bool ok;
  final String message;
  final String? txId;
}

/// Handles cashout requests.
///
/// In [PayoutConfig.demoMode] the request is simulated locally. Flip demoMode to
/// `false` and set [PayoutConfig.backendBaseUrl] to POST real withdrawal
/// requests to your backend (`POST /payouts`), which in turn calls the payout
/// provider (PayPal Payouts, gift-card API, etc.). Never call a payout provider
/// directly from the client — secrets belong on the server.
class PayoutService {
  PayoutService._();
  static final PayoutService instance = PayoutService._();

  /// Requests a withdrawal of [points] via [option].
  Future<PayoutResult> requestCashout({
    required CashoutOption option,
    required int points,
    required String userRef,
  }) async {
    final double cash = PointsMath.pointsToCash(points);

    if (cash < option.minCash) {
      return PayoutResult(
        ok: false,
        message:
            'Minimum for ${option.label} is ${PointsMath.formatCash(option.minCash)}.',
      );
    }

    if (PayoutConfig.demoMode || PayoutConfig.backendBaseUrl.trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return PayoutResult(
        ok: true,
        message:
            'Requested ${PointsMath.formatCash(cash)} via ${option.label} (demo).',
        txId: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    try {
      final http.Response res = await http
          .post(
            Uri.parse('${PayoutConfig.backendBaseUrl}/payouts'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'method': option.id,
              'points': points,
              'cash': cash,
              'userRef': userRef,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final Map<String, dynamic> body =
            (jsonDecode(res.body) as Map).cast<String, dynamic>();
        return PayoutResult(
          ok: true,
          message: 'Cashout submitted.',
          txId: body['txId']?.toString(),
        );
      }
      return PayoutResult(
        ok: false,
        message: 'Server error (${res.statusCode}). Try again later.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PayoutService error: $e');
      return const PayoutResult(
        ok: false,
        message: 'Network error. Check your connection and try again.',
      );
    }
  }
}
