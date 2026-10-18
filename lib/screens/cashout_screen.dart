import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sample_data.dart';
import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/auth_service.dart';
import '../services/payout_service.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import 'earn_screen.dart' show SnackBarHelper;

/// The "Cashout" tab: pick a payout method and request a withdrawal.
///
/// Requests are routed through [PayoutService], which simulates the payout in
/// demo mode and POSTs to your backend (`POST /payouts`) once
/// `PayoutConfig.demoMode` is disabled. On success the points are deducted
/// locally so the balance stays in sync.
class CashoutScreen extends StatelessWidget {
  const CashoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
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
              Text(
                l.t('available_cashout'),
                style: const TextStyle(color: Color(0xCC04121F), fontSize: 13),
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
                l.f('your_points_n', <String, Object?>{
                  'pts': PointsMath.formatPoints(repo.points),
                }),
                style: const TextStyle(color: Color(0xCC04121F), fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: l.t('choose_payout')),
        ...SampleData.cashouts.map((option) {
          final bool eligible = balance >= option.minCash;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CashoutTile(
              option: option,
              eligible: eligible,
              onTap: () => _request(context, option, eligible, repo),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Text(l.t('cashout_footnote'), style: theme.textTheme.bodySmall),
      ],
    );
  }

  void _request(
    BuildContext context,
    CashoutOption option,
    bool eligible,
    PointsRepository repo,
  ) {
    final AppLocalizations l = context.l10n;
    if (!eligible) {
      SnackBarHelper.showError(
        context,
        l.f('not_enough', <String, Object?>{
          'method': option.label,
          'amount': PointsMath.formatCash(option.minCash),
        }),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) =>
          _ConfirmSheet(option: option, points: repo.points),
    );
  }
}

class _CashoutTile extends StatelessWidget {
  const _CashoutTile({
    required this.option,
    required this.eligible,
    required this.onTap,
  });

  final CashoutOption option;
  final bool eligible;
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
                      context.l10n.f('min', <String, Object?>{
                        'amount': PointsMath.formatCash(option.minCash),
                      }),
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

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({required this.option, required this.points});

  final CashoutOption option;
  final int points;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _busy = false;

  Future<void> _submit() async {
    final AppLocalizations l = context.l10n;
    final PointsRepository repo = context.read<PointsRepository>();
    final String userRef =
        AuthService.instance.user.value?.uid ?? 'guest';

    setState(() => _busy = true);
    final PayoutResult res = await PayoutService.instance.requestCashout(
      option: widget.option,
      points: widget.points,
      userRef: userRef,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (res.ok) {
      // Real payout: deduct the points and record the withdrawal.
      repo.spend(
        widget.points,
        title: l.f('cashout_via', <String, Object?>{
          'method': widget.option.label,
        }),
      );
      Navigator.pop(context);
      SnackBarHelper.showReward(context, l.t('cashout_submitted'));
    } else {
      SnackBarHelper.showError(context, res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
    final CashoutOption option = widget.option;
    final int points = widget.points;
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
                  l.f('cashout_via', <String, Object?>{
                    'method': option.label,
                  }),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _row(
            context,
            l.t('your_points'),
            '${PointsMath.formatPoints(points)} pts',
          ),
          _row(
            context,
            l.t('value'),
            PointsMath.formatCash(PointsMath.pointsToCash(points)),
          ),
          _row(
            context,
            l.t('method_minimum'),
            PointsMath.formatCash(option.minCash),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${l.f('withdraw_up_to', <String, Object?>{
              'amount': PointsMath.formatCash(PointsMath.pointsToCash(points)),
            })} '
            '(${PointsMath.formatPoints(needed)} pts = '
            '${PointsMath.formatCash(option.minCash)})',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04121F),
                      ),
                    )
                  : Text(l.t('request_cashout')),
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
