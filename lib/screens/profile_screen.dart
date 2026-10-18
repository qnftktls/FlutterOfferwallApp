import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import 'earn_screen.dart' show SnackBarHelper;
import 'reward_history_screen.dart';

/// The "Profile" tab: account summary, quick stats, and settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PointsRepository repo = context.watch<PointsRepository>();
    final int earned = repo.transactions.fold(0, (sum, t) => sum + t.points);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: <Widget>[
        // Identity card
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.brandPrimary,
                child: Text(
                  'RH',
                  style: TextStyle(
                    color: AppColors.brandAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Guest user', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to sync across devices',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Stats
        Row(
          children: <Widget>[
            _statCard(
              context,
              'Balance',
              repo.cashFormatted,
              '${PointsMath.formatPoints(repo.points)} pts',
            ),
            const SizedBox(width: 10),
            _statCard(
              context,
              'Total earned',
              PointsMath.formatPoints(earned),
              'pts all-time',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        const SectionHeader(title: 'Account'),
        _tile(
          context,
          icon: Icons.receipt_long_rounded,
          title: 'Reward history',
          subtitle: '${repo.transactions.length} transactions',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const RewardHistoryScreen(),
            ),
          ),
        ),
        _tile(
          context,
          icon: Icons.account_balance_wallet_rounded,
          title: 'Cashout methods',
          subtitle: 'PayPal, gift cards, crypto',
          onTap: () => SnackBarHelper.showError(
            context,
            'Open the Cashout tab to withdraw.',
          ),
        ),
        _tile(
          context,
          icon: Icons.help_outline_rounded,
          title: 'Help & support',
          subtitle: 'FAQ and contact',
          onTap: () =>
              SnackBarHelper.showError(context, 'Support is a demo stub.'),
        ),
        _tile(
          context,
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy policy',
          subtitle: 'How your data is used',
          onTap: () =>
              SnackBarHelper.showError(context, 'Policy is a demo stub.'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _tile(
          context,
          icon: Icons.restart_alt_rounded,
          title: 'Reset demo data',
          subtitle: 'Clear points and history',
          danger: true,
          onTap: () => _confirmReset(context, repo),
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    String sub,
  ) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(sub, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  color: danger ? Colors.redAccent : AppColors.brandAccent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: danger ? Colors.redAccent : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    PointsRepository repo,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This clears your points and reward history. Useful for testing.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await repo.reset();
    }
  }
}
