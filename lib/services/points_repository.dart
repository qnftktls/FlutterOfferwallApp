import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offer.dart';

/// Home for the user's reward balance and history.
///
/// Ported from the native `ui/PointsRepository.kt` and upgraded to:
///  - persist the balance AND the transaction history (`shared_preferences`)
///  - expose a USD cash value (`PointsMath`, 1,000 pts = $1)
///  - seed a starter balance so the demo feels alive
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
    return _points;
  }

  /// Records an explicit reward (used for game milestones).
  int credit({required int points, required String title}) =>
      addPoints(points, offerTitle: title);

  /// Resets the balance to zero — useful for logout or debugging.
  Future<void> reset() async {
    _points = 0;
    _transactions.clear();
    await _persist();
    notifyListeners();
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
