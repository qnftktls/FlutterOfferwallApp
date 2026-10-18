import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/auth_service.dart';
import '../services/points_repository.dart';
import '../services/settings_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import 'auth_screen.dart';
import 'earn_screen.dart' show SnackBarHelper;
import 'reward_history_screen.dart';

/// The "Profile" tab: account (Firebase Auth), quick stats, language switch and
/// settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Opens the auth flow; returns true if the user signed in / continued.
  Future<void> _openAuth(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the auth state changes.
    return ValueListenableBuilder<AppUser?>(
      valueListenable: AuthService.instance.user,
      builder: (BuildContext context, AppUser? user, _) =>
          _buildBody(context, user),
    );
  }

  Widget _buildBody(BuildContext context, AppUser? user) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
    final PointsRepository repo = context.watch<PointsRepository>();
    final SettingsRepository settings = context.watch<SettingsRepository>();
    final int earned = repo.transactions
        .where((t) => t.points > 0)
        .fold(0, (sum, t) => sum + t.points);

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
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.brandPrimary,
                child: Text(
                  user?.initials ?? 'RH',
                  style: const TextStyle(
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
                    Text(
                      user == null
                          ? l.t('guest_user')
                          : (user.isGuest
                              ? l.t('guest_user')
                              : user.email),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user == null || user.isGuest
                          ? l.t('sign_in_sync')
                          : l.t('signed_in_as'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Sign in / out button
        if (user == null || user.isGuest)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openAuth(context),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.login_rounded, size: 20),
              label: Text(l.t('sign_in')),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await AuthService.instance.signOut();
              },
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(l.t('sign_out')),
            ),
          ),
        const SizedBox(height: AppSpacing.md),

        // Stats
        Row(
          children: <Widget>[
            _statCard(
              context,
              l.t('balance'),
              repo.cashFormatted,
              '${PointsMath.formatPoints(repo.points)} pts',
            ),
            const SizedBox(width: 10),
            _statCard(
              context,
              l.t('total_earned'),
              PointsMath.formatPoints(earned),
              l.t('pts_all_time'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        SectionHeader(title: l.t('account')),
        _tile(
          context,
          icon: Icons.receipt_long_rounded,
          title: l.t('reward_history'),
          subtitle: l.f('n_transactions', <String, Object?>{
            'n': repo.transactions.length,
          }),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const RewardHistoryScreen(),
            ),
          ),
        ),
        _tile(
          context,
          icon: Icons.account_balance_wallet_rounded,
          title: l.t('cashout_methods'),
          subtitle: l.t('cashout_methods_sub'),
          onTap: () => SnackBarHelper.showError(context, l.t('cashout_stub')),
        ),
        _tile(
          context,
          icon: Icons.translate_rounded,
          title: l.t('language'),
          subtitle: l.t('language_sub'),
          trailing: IgnorePointer(
            child: Switch(
              value: settings.locale.languageCode == 'ko',
              onChanged: (_) {},
            ),
          ),
          onTap: settings.toggleLocale,
        ),
        _tile(
          context,
          icon: Icons.help_outline_rounded,
          title: l.t('help_support'),
          subtitle: l.t('help_sub'),
          onTap: () => SnackBarHelper.showError(context, l.t('support_stub')),
        ),
        _tile(
          context,
          icon: Icons.privacy_tip_outlined,
          title: l.t('privacy_policy'),
          subtitle: l.t('privacy_sub'),
          onTap: () => SnackBarHelper.showError(context, l.t('policy_stub')),
        ),
        const SizedBox(height: AppSpacing.sm),
        _tile(
          context,
          icon: Icons.restart_alt_rounded,
          title: l.t('reset_demo'),
          subtitle: l.t('reset_demo_sub'),
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
    Widget? trailing,
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
                trailing ??
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
    final AppLocalizations l = context.l10n;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.t('reset_title')),
        content: Text(l.t('reset_body')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('reset')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await repo.reset();
    }
  }
}
