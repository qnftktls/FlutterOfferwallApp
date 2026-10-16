/// A single offerwall offer.
///
/// Mirrors the shape the provider's HTML/JS pushes through the bridge.
/// Kept intentionally small: title, reward, category, and an optional icon.
class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.reward,
    required this.accent,
    this.iconEmoji,
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

  /// Parses an offer from the JSON payload a provider page posts via the bridge.
  static Offer fromMap(Map<String, dynamic> map) {
    return Offer(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Offer').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      reward: _toInt(map['reward']),
      accent: (map['accent'] ?? '#00B37E').toString(),
      iconEmoji: map['icon']?.toString(),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'reward': reward,
    'accent': accent,
    'icon': iconEmoji,
  };
}

/// A reward transaction shown in the history screen.
class RewardTransaction {
  const RewardTransaction({
    required this.title,
    required this.points,
    required this.timestamp,
  });

  final String title;
  final int points;
  final DateTime timestamp;
}
