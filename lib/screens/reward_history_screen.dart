import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';

/// Reward history: every credited transaction, newest first.
class RewardHistoryScreen extends StatelessWidget {
  const RewardHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
    final List<RewardTransaction> tx = context
        .watch<PointsRepository>()
        .transactions;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('reward_history'))),
      body: tx.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: AppTheme.muted(context),
                  ),
                  const SizedBox(height: 12),
                  Text(l.t('no_rewards'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    l.t('no_rewards_sub'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: tx.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int i) {
                final RewardTransaction t = tx[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (t.points >= 0
                                  ? AppColors.brandAccent
                                  : Colors.redAccent)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          t.points >= 0
                              ? Icons.add_rounded
                              : Icons.remove_rounded,
                          color: t.points >= 0
                              ? AppColors.brandAccent
                              : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(t.timestamp),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '${t.points >= 0 ? '+' : '-'}'
                            '${PointsMath.formatPoints(t.points.abs())}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: t.points >= 0
                                  ? AppColors.brandAccent
                                  : Colors.redAccent,
                            ),
                          ),
                          Text(
                            PointsMath.formatCash(t.cash.abs()),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
