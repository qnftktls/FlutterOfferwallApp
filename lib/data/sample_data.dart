import '../models/offer.dart';

/// Static sample content for the app demo (Freecash-style).
///
/// In production these come from your backend / offerwall provider. Keeping them
/// here makes the app fully explorable without any accounts.
class SampleData {
  SampleData._();

  static const List<Offer> offers = <Offer>[
    Offer(
      id: '2001',
      title: 'Try a featured game',
      subtitle: 'Playtime · Reach level 5 · ~3 min',
      reward: 250,
      accent: '#00B37E',
      iconEmoji: '🎮',
      category: 'Games',
    ),
    Offer(
      id: '2002',
      title: 'Quick opinion survey',
      subtitle: 'SurveyX · 5 questions · ~2 min',
      reward: 120,
      accent: '#3B82F6',
      iconEmoji: '📋',
      category: 'Surveys',
    ),
    Offer(
      id: '2003',
      title: 'Install & open app',
      subtitle: 'ShopBack · First launch only',
      reward: 80,
      accent: '#F59E0B',
      iconEmoji: '📱',
      category: 'Apps',
    ),
    Offer(
      id: '2004',
      title: 'Start a free trial',
      subtitle: 'FitLoop · No card required',
      reward: 400,
      accent: '#8B5CF6',
      iconEmoji: '🏃',
      category: 'Trials',
    ),
    Offer(
      id: '2005',
      title: 'Sign up for a newsletter',
      subtitle: 'DailyDrop · Email only',
      reward: 60,
      accent: '#EC4899',
      iconEmoji: '✉️',
      category: 'Signups',
    ),
    Offer(
      id: '2006',
      title: 'Watch a product demo',
      subtitle: 'TechView · 90 seconds',
      reward: 95,
      accent: '#06B6D4',
      iconEmoji: '▶️',
      category: 'Videos',
    ),
  ];

  static const List<Mission> missions = <Mission>[
    Mission(
      id: 'game_coin_master',
      game: 'Coin Master',
      tagline: 'Spin & raid to climb levels',
      accent: '#F59E0B',
      iconEmoji: '🪙',
      milestones: <MissionMilestone>[
        MissionMilestone(label: 'Reach level 5', points: 300),
        MissionMilestone(label: 'Reach level 15', points: 900),
        MissionMilestone(label: 'Reach level 30', points: 2_400),
      ],
    ),
    Mission(
      id: 'game_dice_dreams',
      game: 'Dice Dreams',
      tagline: 'Build your kingdom with dice',
      accent: '#EC4899',
      iconEmoji: '🎲',
      milestones: <MissionMilestone>[
        MissionMilestone(label: 'Reach level 8', points: 450),
        MissionMilestone(label: 'Reach level 20', points: 1_500),
      ],
    ),
    Mission(
      id: 'game_puzzle',
      game: 'Royal Match',
      tagline: 'Match to help the king',
      accent: '#8B5CF6',
      iconEmoji: '👑',
      milestones: <MissionMilestone>[
        MissionMilestone(label: 'Complete level 10', points: 250),
        MissionMilestone(label: 'Complete level 50', points: 1_100),
        MissionMilestone(label: 'Complete level 120', points: 3_000),
      ],
    ),
    Mission(
      id: 'game_merge',
      game: 'Merge Mansion',
      tagline: 'Merge items, solve the mystery',
      accent: '#10B981',
      iconEmoji: '🏡',
      milestones: <MissionMilestone>[
        MissionMilestone(label: 'Reach level 6', points: 320),
        MissionMilestone(label: 'Reach level 18', points: 1_200),
      ],
    ),
  ];

  static const List<CashoutOption> cashouts = <CashoutOption>[
    CashoutOption(
      id: 'paypal',
      label: 'PayPal',
      sublabel: 'Cash to your PayPal balance',
      icon: '💳',
      minCash: 5.00,
    ),
    CashoutOption(
      id: 'amazon',
      label: 'Amazon Gift Card',
      sublabel: 'Instant digital delivery',
      icon: '🎁',
      minCash: 5.00,
    ),
    CashoutOption(
      id: 'google',
      label: 'Google Play Gift Card',
      sublabel: 'Use on apps & games',
      icon: '🤖',
      minCash: 5.00,
    ),
    CashoutOption(
      id: 'bitcoin',
      label: 'Bitcoin',
      sublabel: 'Crypto payout (Litecoin too)',
      icon: '₿',
      minCash: 10.00,
    ),
    CashoutOption(
      id: 'visa',
      label: 'Visa Prepaid Card',
      sublabel: 'Digital prepaid card',
      icon: '🏦',
      minCash: 10.00,
    ),
  ];
}
