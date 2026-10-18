import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'points_repository.dart';

/// Result of a server-verified reward claim.
class ClaimResult {
  const ClaimResult({
    required this.ok,
    this.credited = 0,
    this.duplicated = false,
    this.error,
    this.fromServer = false,
  });

  /// Whether the reward was accepted.
  final bool ok;

  /// Points the SERVER decided to credit (authoritative).
  final int credited;

  /// True when the server recognised this as an already-processed claim.
  final bool duplicated;

  /// Human-readable error (localized by the caller if needed).
  final String? error;

  /// True when the value came from Cloud Functions; false when we fell back
  /// to the local demo path (Functions not deployed / offline).
  final bool fromServer;
}

/// Client wrapper around the anti-fraud Cloud Functions.
///
/// ## Why this matters
///
/// The app must NEVER decide how many points an offer is worth. Two supported
/// flows:
///
/// * **Production** — the offerwall provider's backend calls
///   `offerwallPostback` (server-to-server, HMAC-signed). The app just pulls
///   the new balance. No client input at all.
/// * **Instant / demo offers** — the app calls `claimOffer` with only an
///   `offerId`; the **server** looks up the authoritative amount in its price
///   table and credits it. A tampered client cannot inflate the reward.
///
/// Both are wrapped here with a graceful fallback: if Cloud Functions are not
/// deployed yet (or the device is offline), [claimOffer] reports
/// `fromServer = false` so the caller can decide whether to fall back to the
/// local demo credit.
class RewardService {
  RewardService._();
  static final RewardService instance = RewardService._();

  bool _firebaseReady = false;

  /// Mirrors whether Firebase initialized (set from `main()`).
  void markReady(bool ready) => _firebaseReady = ready;

  FirebaseFunctions? get _fn {
    if (!_firebaseReady) return null;
    try {
      return FirebaseFunctions.instance;
    } catch (_) {
      return null;
    }
  }

  /// Whether the Cloud Functions backend is reachable.
  bool get isAvailable => _fn != null;

  /// Asks the server to credit an offer.
  ///
  /// [offerId] is the ONLY thing the client provides — the reward amount is
  /// decided server-side. Pass [idempotencyKey] to make retries safe.
  Future<ClaimResult> claimOffer({
    required String offerId,
    String? idempotencyKey,
  }) async {
    final FirebaseFunctions? fn = _fn;
    if (fn == null) {
      return const ClaimResult(ok: false, error: 'Cloud Functions unavailable');
    }

    try {
      final HttpsCallableResult<dynamic> res = await fn
          .httpsCallable('claimOffer')
          .call<dynamic>(<String, dynamic>{
            'offerId': offerId,
            if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
          })
          .timeout(const Duration(seconds: 20));

      final Map<dynamic, dynamic> data =
          (res.data as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
      final bool ok = data['ok'] == true;
      final int balance = _asInt(data['balance']);

      // Reconcile the local balance with the authoritative server value.
      if (ok && balance >= 0) {
        await PointsRepository.instance.adoptServerBalance(balance);
      }

      return ClaimResult(
        ok: ok,
        credited: _asInt(data['credited']),
        duplicated: data['duplicated'] == true,
        fromServer: true,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('claimOffer failed: ${e.code} ${e.message}');
      return ClaimResult(ok: false, error: e.message ?? e.code, fromServer: true);
    } catch (e) {
      if (kDebugMode) debugPrint('claimOffer error: $e');
      return ClaimResult(ok: false, error: e.toString());
    }
  }

  /// Requests a withdrawal through the server (authoritative balance check).
  ///
  /// Returns the new balance on success, or an error message.
  Future<PayoutCallResult> requestPayout({
    required String method,
    required int points,
  }) async {
    final FirebaseFunctions? fn = _fn;
    if (fn == null) {
      return const PayoutCallResult(
        ok: false,
        error: 'Cloud Functions unavailable',
      );
    }

    try {
      final HttpsCallableResult<dynamic> res = await fn
          .httpsCallable('requestPayout')
          .call<dynamic>(<String, dynamic>{
            'method': method,
            'points': points,
          })
          .timeout(const Duration(seconds: 30));

      final Map<dynamic, dynamic> data =
          (res.data as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
      final bool ok = data['ok'] == true;
      final int balance = _asInt(data['balance']);
      if (ok && balance >= 0) {
        await PointsRepository.instance.adoptServerBalance(balance);
      }
      return PayoutCallResult(
        ok: ok,
        message: data['message']?.toString(),
        balance: balance,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('requestPayout failed: ${e.code} ${e.message}');
      return PayoutCallResult(ok: false, error: e.message ?? e.code);
    } catch (e) {
      if (kDebugMode) debugPrint('requestPayout error: $e');
      return PayoutCallResult(ok: false, error: e.toString());
    }
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? -1;
    return -1;
  }
}

/// Result of a server-side payout request.
class PayoutCallResult {
  const PayoutCallResult({
    required this.ok,
    this.message,
    this.error,
    this.balance,
  });

  final bool ok;
  final String? message;
  final String? error;
  final int? balance;
}
