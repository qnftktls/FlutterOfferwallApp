import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sample_data.dart';
import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import 'earn_screen.dart' show SnackBarHelper;

/// The "Games" tab: install-a-game missions with escalating milestone rewards,
/// inspired by Freecash's most popular offer type.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: <Widget>[
              const Text('🎮', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.t('play_earn_big'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.t('play_earn_sub'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionHeader(title: l.t('game_missions')),
        ...SampleData.missions.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MissionCard(mission: m),
          ),
        ),
      ],
    );
  }
}

class _MissionCard extends StatefulWidget {
  const _MissionCard({required this.mission});

  final Mission mission;

  @override
  State<_MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends State<_MissionCard> {
  /// Indices of milestones already claimed.
  final Set<int> _claimed = <int>{};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
    final Mission m = widget.mission;
    final Color accent = hexColor(m.accent);
    final int claimedPoints = _claimed.fold(
      0,
      (sum, i) => sum + m.milestones[i].points,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(m.iconEmoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(m.game, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(m.tagline, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    l.t('up_to'),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                  Text(
                    PointsMath.formatCash(
                      PointsMath.pointsToCash(m.totalPoints),
                    ),
                    style: TextStyle(
                      color: theme.colorScheme.brightness == Brightness.dark
                          ? AppColors.brandAccent
                          : accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Progress bar across claimed milestones.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: m.milestones.isEmpty
                  ? 0
                  : _claimed.length / m.milestones.length,
              minHeight: 8,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.f('milestones', <String, Object?>{
              'done': _claimed.length,
              'total': m.milestones.length,
              'pts': PointsMath.formatPoints(claimedPoints),
            }),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ...List<Widget>.generate(m.milestones.length, (int i) {
            final MissionMilestone ms = m.milestones[i];
            final bool done = _claimed.contains(i);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: done ? accent : theme.dividerColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ms.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? AppTheme.muted(context) : null,
                      ),
                    ),
                  ),
                  Text(
                    '+${PointsMath.formatPoints(ms.points)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: done
                          ? AppTheme.muted(context)
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: FilledButton(
                      onPressed: done ? null : () => _claim(i),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(done ? l.t('done') : l.t('claim')),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _claim(int index) {
    final AppLocalizations l = context.l10n;
    final Mission m = widget.mission;
    final MissionMilestone ms = m.milestones[index];
    if (_claimed.contains(index)) return;

    context.read<PointsRepository>().credit(
      points: ms.points,
      title: '${m.game} · ${ms.label}',
    );

    setState(() => _claimed.add(index));
    SnackBarHelper.showReward(
      context,
      l.f('game_reward', <String, Object?>{
        'game': m.game,
        'pts': PointsMath.formatPoints(ms.points),
      }),
    );
  }
}
