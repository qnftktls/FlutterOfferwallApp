import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';

/// Reward history: every credited transaction, newest first.
class RewardHistoryScreen extends StatelessWidget {
  const RewardHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<RewardTransaction> tx = context
        .watch<PointsRepository>()
        .transactions;

    return Scaffold(
      appBar: AppBar(title: const Text('Reward history')),
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
                  Text('No rewards yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Complete an offer to see it here.',
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
                          color: AppColors.brandAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppColors.brandAccent,
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
                            '+${PointsMath.formatPoints(t.points)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandAccent,
                            ),
                          ),
                          Text(
                            PointsMath.formatCash(t.cash),
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
