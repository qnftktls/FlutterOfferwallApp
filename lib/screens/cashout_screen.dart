import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sample_data.dart';
import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import 'earn_screen.dart' show SnackBarHelper;

/// The "Cashout" tab: pick a payout method and (demo) request a withdrawal.
/// Real payout integration is provider/backend work — this is the full UI flow.
class CashoutScreen extends StatelessWidget {
  const CashoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PointsRepository repo = context.watch<PointsRepository>();
    final double balance = repo.cashValue;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: <Widget>[
        // Balance hero
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[AppColors.brandAccent, Color(0xFF12D39D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Available to cash out',
                style: TextStyle(color: Color(0xCC04121F), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                repo.cashFormatted,
                style: const TextStyle(
                  color: Color(0xFF04121F),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                '${PointsMath.formatPoints(repo.points)} points',
                style: const TextStyle(color: Color(0xCC04121F), fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Choose a payout method'),
        ...SampleData.cashouts.map((option) {
          final bool eligible = balance >= option.minCash;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CashoutTile(
              option: option,
              eligible: eligible,
              balance: balance,
              onTap: () => _request(context, option, eligible, repo.points),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Minimums shown per method. In production these payouts are fulfilled '
          'by your backend + the provider; this demo only simulates the request.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  void _request(
    BuildContext context,
    CashoutOption option,
    bool eligible,
    int points,
  ) {
    if (!eligible) {
      SnackBarHelper.showError(
        context,
        'Not enough balance. ${option.label} needs '
        '${PointsMath.formatCash(option.minCash)}.',
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) =>
          _ConfirmSheet(option: option, points: points),
    );
  }
}

class _CashoutTile extends StatelessWidget {
  const _CashoutTile({
    required this.option,
    required this.eligible,
    required this.balance,
    required this.onTap,
  });

  final CashoutOption option;
  final bool eligible;
  final double balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Opacity(
      opacity: eligible ? 1 : 0.55,
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
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    option.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(option.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(option.sublabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'min ${PointsMath.formatCash(option.minCash)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(
                      eligible
                          ? Icons.chevron_right_rounded
                          : Icons.lock_outline_rounded,
                      size: 18,
                      color: AppTheme.muted(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.option, required this.points});

  final CashoutOption option;
  final int points;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int needed = PointsMath.cashToPoints(option.minCash);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(option.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cash out via ${option.label}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _row(
            context,
            'Your points',
            '${PointsMath.formatPoints(points)} pts',
          ),
          _row(
            context,
            'Value',
            PointsMath.formatCash(PointsMath.pointsToCash(points)),
          ),
          _row(
            context,
            'Method minimum',
            PointsMath.formatCash(option.minCash),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You could withdraw up to '
            '${PointsMath.formatCash(PointsMath.pointsToCash(points))} '
            '(${PointsMath.formatPoints(needed)} pts = ${PointsMath.formatCash(option.minCash)}).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                SnackBarHelper.showReward(
                  context,
                  'Cashout request submitted (demo)!',
                );
              },
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: const Text('Request cashout'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
