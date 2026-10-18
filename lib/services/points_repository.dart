import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offer.dart';
import 'sync_service.dart';

/// Home for the user's reward balance and history.
///
/// Ported from the native `ui/PointsRepository.kt` and upgraded to:
///  - persist the balance AND the transaction history (`shared_preferences`)
///  - expose a USD cash value (`PointsMath`, 1,000 pts = $1)
///  - seed a starter balance so the demo feels alive
///  - **sync across devices** through Cloud Firestore (see [SyncService])
class PointsRepository extends ChangeNotifier {
  PointsRepository._();

  static final PointsRepository instance = PointsRepository._();

  static const String _pointsKey = 'rewards.points.v2';
  static const String _txKey = 'rewards.transactions.v2';
  static const int _seedPoints = 1_250;

  int _points = 0;
  int get points => _points;

  /// Balance expressed in USD.
  double get cashValue => PointsMath.pointsToCash(_points);
  String get cashFormatted => PointsMath.formatCash(cashValue);

  final List<RewardTransaction> _transactions = <RewardTransaction>[];
  List<RewardTransaction> get transactions => List.unmodifiable(_transactions);

  SharedPreferences? _prefs;

  /// The signed-in user id whose cloud document mirrors this state (null when
  /// signed out / guest). Set via [bindUser].
  String? _uid;

  /// Live sync state for the UI.
  SyncStatus get syncStatus => SyncService.instance.status.value;

  /// Loads the persisted balance + history. Call once during app startup.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final bool hasStored = _prefs?.containsKey(_pointsKey) ?? false;
      _points = _prefs?.getInt(_pointsKey) ?? 0;

      final String? rawTx = _prefs?.getString(_txKey);
      _transactions
        ..clear()
        ..addAll(_decodeTransactions(rawTx));

      // First launch: seed a welcome balance so the demo isn't empty.
      if (!hasStored) {
        _points = _seedPoints;
        _transactions.insert(
          0,
          RewardTransaction(
            title: 'Welcome bonus',
            points: _seedPoints,
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        );
        await _persist();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PointsRepository.load failed: $e');
      _points = 0;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cloud sync
  // ---------------------------------------------------------------------------

  /// Attaches (or detaches, with `null`) the signed-in user and syncs.
  ///
  /// On sign-in the cloud document is fetched and merged: the **cloud is the
  /// source of truth** when it already has data, otherwise the local state is
  /// pushed up (first-device case).
  Future<void> bindUser(String? uid) async {
    _uid = uid;
    if (uid == null) {
      SyncService.instance.reset();
      notifyListeners();
      return;
    }

    final CloudSnapshot? cloud = await SyncService.instance.pull(uid);
    if (cloud != null && (cloud.transactions.isNotEmpty || cloud.points > 0)) {
      // Cloud wins — adopt its balance + history.
      _points = cloud.points;
      _transactions
        ..clear()
        ..addAll(
          cloud.transactions..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
      await _persist();
      notifyListeners();
    } else {
      // No cloud data yet — seed the cloud from this device.
      await _pushToCloud();
    }
  }

  /// Adds (or subtracts, with a negative delta) points and returns the new balance.
  int addPoints(int delta, {String? offerTitle, String? offerId}) {
    _points = (_points + delta).clamp(0, 1 << 31);
    if (delta > 0) {
      _transactions.insert(
        0,
        RewardTransaction(
          title: offerTitle ?? 'Offer completed',
          points: delta,
          timestamp: DateTime.now(),
          offerId: offerId,
        ),
      );
    }
    _persistSoon();
    notifyListeners();
    _pushSoon();
    return _points;
  }

  /// Records an explicit reward (used for game milestones).
  int credit({required int points, required String title}) =>
      addPoints(points, offerTitle: title);

  /// Deducts points for a withdrawal and records it in the history.
  ///
  /// Returns the new balance. Callers should check eligibility *before*
  /// calling this (see `PayoutService`).
  int spend(int points, {required String title}) {
    final int amount = points.abs();
    _points = (_points - amount).clamp(0, 1 << 31);
    _transactions.insert(
      0,
      RewardTransaction(
        title: title,
        points: -amount,
        timestamp: DateTime.now(),
      ),
    );
    _persistSoon();
    notifyListeners();
    _pushSoon();
    return _points;
  }

  /// Resets the balance to zero — useful for logout or debugging.
  Future<void> reset() async {
    _points = 0;
    _transactions.clear();
    await _persist();
    if (_uid != null) {
      await SyncService.instance.clear(_uid!);
    }
    notifyListeners();
  }

  /// Manually forces a cloud push (used by the Profile "Sync now" action).
  Future<void> syncNow() async {
    if (_uid == null) return;
    await _pushToCloud();
  }

  /// Adopts the balance the **server** reports as authoritative.
  ///
  /// Used after a server-verified claim or payout: the Cloud Function already
  /// computed the new balance, so we trust it over our local arithmetic. The
  /// local transaction list is refreshed with a pull instead of being mutated,
  /// because the server owns the history.
  Future<void> adoptServerBalance(int serverBalance) async {
    _points = serverBalance.clamp(0, 1 << 31);
    await _persist();
    notifyListeners();

    // Re-pull the authoritative history so the UI matches the server.
    final String? uid = _uid;
    if (uid != null) {
      final CloudSnapshot? cloud = await SyncService.instance.pull(uid);
      if (cloud != null && cloud.transactions.isNotEmpty) {
        _transactions
          ..clear()
          ..addAll(
            cloud.transactions
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          );
        await _persist();
        notifyListeners();
      }
    }
  }

  Future<void> _pushToCloud() async {
    final String? uid = _uid;
    if (uid == null) return;
    await SyncService.instance.push(
      uid: uid,
      points: _points,
      transactions: _transactions,
    );
    notifyListeners();
  }

  void _pushSoon() {
    if (_uid == null) return;
    // Fire-and-forget: never blocks the UI on the network.
    _pushToCloud().ignore();
  }

  List<RewardTransaction> _decodeTransactions(String? raw) {
    if (raw == null || raw.isEmpty) return <RewardTransaction>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (m) => RewardTransaction.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Transactions decode failed: $e');
    }
    return <RewardTransaction>[];
  }

  void _persistSoon() {
    _persist().ignore();
  }

  Future<void> _persist() async {
    try {
      await _prefs?.setInt(_pointsKey, _points);
      await _prefs?.setString(
        _txKey,
        jsonEncode(_transactions.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PointsRepository.persist failed: $e');
    }
  }
}
