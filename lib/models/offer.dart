import 'dart:convert';

/// A single offerwall offer.
///
/// Mirrors the shape the provider's HTML/JS pushes through the bridge.
class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.reward,
    required this.accent,
    this.iconEmoji,
    this.category = 'Featured',
  });

  /// Provider offer id — used for reconciliation / analytics.
  final String id;

  /// Short headline, e.g. "Install & reach level 5".
  final String title;

  /// Secondary line, e.g. category or provider name.
  final String subtitle;

  /// Points credited on completion.
  final int reward;

  /// Accent hex string (e.g. "#00B37E") used to tint the card.
  final String accent;

  /// Optional leading emoji (placeholder pages use this instead of image assets).
  final String? iconEmoji;

  /// Grouping label shown as a chip, e.g. "Games", "Surveys".
  final String category;

  /// Parses an offer from the JSON payload a provider page posts via the bridge.
  static Offer fromMap(Map<String, dynamic> map) {
    return Offer(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Offer').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      reward: toInt(map['reward']),
      accent: (map['accent'] ?? '#00B37E').toString(),
      iconEmoji: map['icon']?.toString(),
      category: (map['category'] ?? 'Featured').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'reward': reward,
    'accent': accent,
    'icon': iconEmoji,
    'category': category,
  };

  /// Whether the offer came from the live JS bridge (numeric id).
  bool get isFromBridge => int.tryParse(id) != null;
}

/// A single milestone inside a game mission (e.g. "Reach level 5").
class MissionMilestone {
  const MissionMilestone({required this.label, required this.points});

  final String label;
  final int points;
}

/// A game mission: install a game and hit milestones for escalating rewards.
///
/// Modeled after Freecash's popular "play games for rewards" offers.
class Mission {
  const Mission({
    required this.id,
    required this.game,
    required this.tagline,
    required this.accent,
    required this.iconEmoji,
    required this.milestones,
  });

  final String id;
  final String game;
  final String tagline;
  final String accent;
  final String iconEmoji;
  final List<MissionMilestone> milestones;

  /// Total points available if every milestone is reached.
  int get totalPoints => milestones.fold(0, (sum, m) => sum + m.points);

  /// Parses a mission from the offerwall bridge (optional support).
  static Mission fromMap(Map<String, dynamic> map) {
    final List<dynamic> raw = (map['milestones'] as List<dynamic>?) ?? const [];
    return Mission(
      id: (map['id'] ?? '').toString(),
      game: (map['game'] ?? 'Game').toString(),
      tagline: (map['tagline'] ?? '').toString(),
      accent: (map['accent'] ?? '#00B37E').toString(),
      iconEmoji: (map['icon'] ?? '🎮').toString(),
      milestones: raw
          .whereType<Map>()
          .map(
            (m) => MissionMilestone(
              label: (m['label'] ?? '').toString(),
              points: toInt(m['points']),
            ),
          )
          .toList(),
    );
  }
}

/// A payout method shown on the cashout screen (PayPal, gift card, crypto…).
class CashoutOption {
  const CashoutOption({
    required this.id,
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.minCash,
    this.accent,
  });

  final String id;
  final String label;
  final String sublabel;
  final String icon; // emoji
  final double minCash; // minimum USD to withdraw
  final int? accent; // optional tint color
}

/// A reward transaction shown in the history screen.
class RewardTransaction {
  const RewardTransaction({
    required this.title,
    required this.points,
    required this.timestamp,
    this.offerId,
  });

  final String title;
  final int points;
  final DateTime timestamp;
  final String? offerId;

  double get cash => PointsMath.pointsToCash(points);

  Map<String, dynamic> toJson() => {
    'title': title,
    'points': points,
    'timestamp': timestamp.toIso8601String(),
    'offerId': offerId,
  };

  static RewardTransaction fromJson(Map<String, dynamic> map) {
    return RewardTransaction(
      title: (map['title'] ?? 'Reward').toString(),
      points: toInt(map['points']),
      timestamp:
          DateTime.tryParse((map['timestamp'] ?? '').toString()) ??
          DateTime.now(),
      offerId: map['offerId']?.toString(),
    );
  }
}

/// Points ⇄ USD conversion. 1,000 points = $1.00 (a Freecash-style ratio).
class PointsMath {
  PointsMath._();

  /// Points required for one US dollar.
  static const int pointsPerDollar = 1000;

  static double pointsToCash(int points) => points / pointsPerDollar;

  static int cashToPoints(double cash) => (cash * pointsPerDollar).round();

  /// Formats points as a USD string, e.g. `$1.25`.
  static String formatCash(double cash) => '\$${cash.toStringAsFixed(2)}';

  /// Formats an int with thousands separators, e.g. `1,250`.
  static String formatPoints(int value) {
    final String digits = value.abs().toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${value < 0 ? '-' : ''}$buffer';
  }
}

/// Shared safe int coercion used by every model parser.
int toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Decodes a JSON payload into a map (returns `{}` when malformed).
Map<String, dynamic> decodeMap(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {
    // ignore: avoid_print
  }
  return <String, dynamic>{};
}
