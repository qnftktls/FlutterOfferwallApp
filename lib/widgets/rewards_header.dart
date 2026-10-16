import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/points_repository.dart';
import '../theme/app_theme.dart';

/// The home header: app name on the left, live points balance pill on the right.
///
/// Ported from the native `activity_main.xml` header block. Observes
/// [PointsRepository] so the balance updates the moment an offer completes.
class RewardsHeader extends StatelessWidget {
  const RewardsHeader({super.key, this.onTapBalance});

  final VoidCallback? onTapBalance;

  @override
  Widget build(BuildContext context) {
    final int points = context.select<PointsRepository, int>((r) => r.points);
    final ThemeData theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Rewards Hub',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTapBalance,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.stars_rounded,
                      size: 18,
                      color: AppColors.brandAccent,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${_format(points)} pts',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _format(int value) {
    final String digits = value.toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
