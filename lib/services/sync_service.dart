import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/offer.dart';

/// Sync lifecycle state surfaced to the UI.
enum SyncStatus {
  /// Firestore unavailable / user signed out — the app runs locally only.
  offline,

  /// A sync round-trip is in flight.
  syncing,

  /// Cloud data is up to date (last successful sync).
  synced,

  /// The sync attempt failed (network / rules / API disabled).
  error,
}

/// Cross-device sync of the reward balance + history via Cloud Firestore.
///
/// Data model (kept intentionally simple to avoid composite indexes):
///
/// ```
/// users/{uid}                      <- document
///   points: int
///   updatedAt: timestamp
///   tx: [ {title, points, timestamp, offerId}, ... ]   // embedded array
/// ```
///
/// The transaction history is stored **inline as an array field** on the user
/// document rather than in a subcollection. That means every read/write is a
/// single-document operation — no `where()`/`orderBy()` combination, so **no
/// composite index is ever required**.
///
/// Every method degrades gracefully: if Firestore is unavailable (API not
/// enabled, no network, security rules deny), the app keeps working from local
/// storage and the status is reported as [SyncStatus.offline] / [SyncStatus.error].
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const String _collection = 'users';
  static const int maxHistory = 200;

  bool _firebaseReady = false;

  /// Mirrors whether Firebase initialized (set from `main()`).
  void markReady(bool ready) => _firebaseReady = ready;

  final ValueNotifier<SyncStatus> status =
      ValueNotifier<SyncStatus>(SyncStatus.offline);

  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);

  FirebaseFirestore? get _db {
    if (!_firebaseReady) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Whether cloud sync is currently possible at all.
  bool get isAvailable => _db != null;

  /// Pushes the local state up to Firestore (write-through).
  ///
  /// Called after every balance change while signed in. Failures never throw —
  /// they just flip [status] to [SyncStatus.error].
  Future<void> push({
    required String uid,
    required int points,
    required List<RewardTransaction> transactions,
  }) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty || uid == 'guest' || uid == 'local') {
      status.value = SyncStatus.offline;
      return;
    }

    status.value = SyncStatus.syncing;
    try {
      final List<Map<String, dynamic>> tx = transactions
          .take(maxHistory)
          .map((t) => t.toJson())
          .toList();

      await db
          .collection(_collection)
          .doc(uid)
          .set(<String, dynamic>{
            'points': points,
            'tx': tx,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));

      status.value = SyncStatus.synced;
      lastSyncedAt.value = DateTime.now();
    } catch (e) {
      _log('push failed', e);
      status.value = SyncStatus.error;
    }
  }

  /// Reads the cloud state for [uid].
  ///
  /// The caller decides how to merge (see `PointsRepository.syncFromCloud`).
  /// Returns `null` when there is nothing to merge / Firestore is unavailable.
  Future<CloudSnapshot?> pull(String uid) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty || uid == 'guest' || uid == 'local') {
      status.value = SyncStatus.offline;
      return null;
    }

    status.value = SyncStatus.syncing;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection(_collection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));

      status.value = SyncStatus.synced;
      lastSyncedAt.value = DateTime.now();

      if (!doc.exists) return null;
      final Map<String, dynamic>? data = doc.data();
      if (data == null) return null;

      final int points = toInt(data['points']);
      final List<RewardTransaction> tx = <RewardTransaction>[];
      final Object? rawTx = data['tx'];
      if (rawTx is List) {
        for (final Object? item in rawTx) {
          if (item is Map) {
            tx.add(
              RewardTransaction.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
      }

      DateTime? updatedAt;
      final Object? upd = data['updatedAt'];
      if (upd is Timestamp) updatedAt = upd.toDate();

      return CloudSnapshot(points: points, transactions: tx, updatedAt: updatedAt);
    } catch (e) {
      _log('pull failed', e);
      status.value = SyncStatus.error;
      return null;
    }
  }

  /// Wipes the cloud document (used by "reset demo data" while signed in).
  Future<void> clear(String uid) async {
    final FirebaseFirestore? db = _db;
    if (db == null || uid.isEmpty || uid == 'guest' || uid == 'local') return;
    try {
      await db.collection(_collection).doc(uid).delete();
    } catch (e) {
      _log('clear failed', e);
    }
  }

  void reset() {
    status.value = SyncStatus.offline;
    lastSyncedAt.value = null;
  }

  void _log(String msg, Object e) {
    if (kDebugMode) debugPrint('SyncService.$msg: $e');
  }
}

/// A single cloud document snapshot for one user.
class CloudSnapshot {
  const CloudSnapshot({
    required this.points,
    required this.transactions,
    this.updatedAt,
  });

  final int points;
  final List<RewardTransaction> transactions;
  final DateTime? updatedAt;

  /// Total positive points ever earned (derived, not stored).
  int get totalEarned =>
      transactions.where((t) => t.points > 0).fold(0, (s, t) => s + t.points);

  /// Convenience for debugging / logging.
  String toDebugString() =>
      'CloudSnapshot(points=$points, tx=${transactions.length}, '
      'updatedAt=$updatedAt)';

  /// Encodes to JSON (used by tests and optional export).
  String toJsonString() => jsonEncode(<String, dynamic>{
        'points': points,
        'tx': transactions.map((t) => t.toJson()).toList(),
      });
}
