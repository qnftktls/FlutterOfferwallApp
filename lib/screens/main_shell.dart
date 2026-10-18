import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sample_data.dart';
import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import 'cashout_screen.dart';
import 'earn_screen.dart';
import 'games_screen.dart';
import 'profile_screen.dart';

/// The app shell: a persistent balance header + bottom navigation across the
/// four Freecash-style sections (Earn / Games / Cashout / Profile).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final PageController _pageController;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(Icons.redeem_rounded, Icons.redeem_outlined, 'Earn'),
    _NavItem(
      Icons.sports_esports_rounded,
      Icons.sports_esports_outlined,
      'Games',
    ),
    _NavItem(
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
      'Cashout',
    ),
    _NavItem(Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _select(int i) {
    setState(() => _index = i);
    _pageController.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: <Widget>[
          const _ShellHeader(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _index = i),
              children: <Widget>[
                EarnScreen(onOpenGames: () => _select(1)),
                const GamesScreen(),
                const CashoutScreen(),
                const ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: AppColors.brandAccent.withValues(alpha: 0.16),
        destinations: _items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(
                  item.iconActive,
                  color: AppColors.brandAccent,
                ),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.iconActive, this.label);
  final IconData icon;
  final IconData iconActive;
  final String label;
}

/// The persistent header: brand mark, live balance in points, and USD value.
class _ShellHeader extends StatelessWidget {
  const _ShellHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PointsRepository repo = context.watch<PointsRepository>();
    final List<RewardTransaction> tx = repo.transactions;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[
                          AppColors.brandPrimary,
                          Color(0xFF14507F),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.stars_rounded,
                      color: AppColors.brandAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Rewards Hub', style: theme.textTheme.titleMedium),
                        Text(
                          '${SampleData.offers.length + SampleData.missions.length} offers available',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _BalancePill(points: repo.points, cash: repo.cashFormatted),
                ],
              ),
            ),
            // A subtle "latest reward" ticker, like Freecash's activity feed.
            if (tx.isNotEmpty)
              Container(
                width: double.infinity,
                color: AppColors.brandAccent.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: AppColors.brandAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Latest: ${tx.first.title}  +${PointsMath.formatPoints(tx.first.points)} pts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
          ],
        ),
      ),
    );
  }
}

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.points, required this.cash});

  final int points;
  final String cash;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.brandAccent, Color(0xFF12D39D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            cash,
            style: const TextStyle(
              color: Color(0xFF04121F),
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.1,
            ),
          ),
          Text(
            '${PointsMath.formatPoints(points)} pts',
            style: const TextStyle(
              color: Color(0xFF04121F),
              fontSize: 10.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
