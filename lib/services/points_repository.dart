import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offer.dart';

/// Home for the user's reward balance.
///
/// Ported from the native `ui/PointsRepository.kt`, but upgraded from an
/// in-memory [StateFlow] to a persistence-backed [ChangeNotifier] so the balance
/// survives app restarts (`shared_preferences`).
///
/// Replace this with your real source of truth (Hive / Room-equivalent / your
/// backend) without touching the UI: widgets only listen to [points] and
/// [transactions].
class PointsRepository extends ChangeNotifier {
  PointsRepository._();

  static final PointsRepository instance = PointsRepository._();

  static const String _pointsKey = 'rewards.points.v1';

  int _points = 0;
  int get points => _points;

  final List<RewardTransaction> _transactions = <RewardTransaction>[];
  List<RewardTransaction> get transactions => List.unmodifiable(_transactions);

  SharedPreferences? _prefs;

  /// Loads the persisted balance. Call once during app startup.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _points = _prefs?.getInt(_pointsKey) ?? 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PointsRepository.load failed: $e');
      }
      _points = 0;
    }
    notifyListeners();
  }

  /// Adds (or subtracts, with a negative delta) points and returns the new balance.
  int addPoints(int delta, {String? offerTitle}) {
    _points = (_points + delta).clamp(0, 1 << 31);
    if (delta > 0) {
      _transactions.insert(
        0,
        RewardTransaction(
          title: offerTitle ?? 'Offer completed',
          points: delta,
          timestamp: DateTime.now(),
        ),
      );
    }
    unawaited(_persist());
    notifyListeners();
    return _points;
  }

  /// Resets the balance to zero — useful for logout or debugging.
  Future<void> reset() async {
    _points = 0;
    _transactions.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs?.setInt(_pointsKey, _points);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PointsRepository.persist failed: $e');
      }
    }
  }
}

/// Fire-and-forget helper so [addPoints] can stay synchronous.
void unawaited(Future<void> future) {
  future.ignore();
}
