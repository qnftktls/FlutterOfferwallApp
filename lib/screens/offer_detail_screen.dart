import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/interstitial.dart';
import '../services/points_repository.dart';
import '../services/reward_service.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad.dart';
import '../widgets/offer_card.dart';
import 'earn_screen.dart' show SnackBarHelper;

/// Detail screen for a single offer. Freecash-style: shows terms, a big CTA,
/// a bottom banner, and (on mobile) a full-screen interstitial on entry.
class OfferDetailScreen extends StatefulWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final Offer offer;

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  bool _completed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Pre-load and show an interstitial, mirroring the native
    // AdIds.INTERSTITIAL_OFFER_DETAIL usage.
    final InterstitialAdManager ads = InterstitialAdManager.instance;
    ads.preload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ads.showIfAvailable();
    });
  }

  /// Completes the offer.
  ///
  /// ## Anti-fraud
  /// When [SecurityConfig.useServerVerification] is on, the reward is credited
  /// by the **server** (`claimOffer` Cloud Function), which looks up the
  /// authoritative amount itself — the client only sends the offer id. If the
  /// backend is unreachable the app falls back to the local demo credit so the
  /// UX never breaks (and the Profile sync card shows "offline").
  Future<void> _completeOffer() async {
    if (_completed || _busy) return;
    final AppLocalizations l = context.l10n;
    final PointsRepository repo = context.read<PointsRepository>();

    // ---- Server-verified path (production / anti-fraud) ----
    if (SecurityConfig.useServerVerification && RewardService.instance.isAvailable) {
      setState(() => _busy = true);
      final ClaimResult res = await RewardService.instance.claimOffer(
        offerId: widget.offer.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);

      if (res.ok) {
        setState(() => _completed = true);
        SnackBarHelper.showReward(
          context,
          l.f('earned_points', <String, Object?>{
            'pts': PointsMath.formatPoints(widget.offer.reward),
          }),
        );
        return;
      }

      // Server reachable but rejected (unknown offer / already claimed) — do
      // NOT credit locally, that would defeat the whole point.
      if (res.fromServer) {
        SnackBarHelper.showError(
          context,
          res.duplicated ? l.t('already_claimed') : (res.error ?? l.t('claim_failed')),
        );
        return;
      }
    }

    // ---- Local demo fallback (Functions not deployed / offline) ----
    repo.addPoints(
      widget.offer.reward,
      offerTitle: widget.offer.title,
      offerId: widget.offer.id,
    );
    setState(() => _completed = true);
    SnackBarHelper.showReward(
      context,
      l.f('earned_points', <String, Object?>{
        'pts': PointsMath.formatPoints(widget.offer.reward),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;
    final Offer offer = widget.offer;
    final Color accent = hexColor(offer.accent);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('offer_details')),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      offer.iconEmoji ?? '★',
                      style: const TextStyle(fontSize: 40),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(offer.title, style: theme.textTheme.titleLarge),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(offer.subtitle, style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: AppSpacing.lg),
                _rewardBox(context, offer, accent),
                const SizedBox(height: AppSpacing.md),
                SectionHeader(title: l.t('how_to_complete')),
                _step('1', l.t('step1')),
                _step('2', l.t('step2')),
                _step('3', l.t('step3')),
                const SizedBox(height: AppSpacing.md),
                SectionHeader(title: l.t('terms')),
                Text(
                  l.t('terms_body'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Divider(height: 1, color: theme.dividerColor),
                const BannerAdWidget(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_completed || _busy) ? null : _completeOffer,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: _completed
                            ? theme.dividerColor
                            : AppColors.brandAccent,
                        foregroundColor: const Color(0xFF04121F),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF04121F),
                              ),
                            )
                          : Text(
                              _completed
                                  ? l.t('completed')
                                  : l.f('start_offer', <String, Object?>{
                                      'pts':
                                          PointsMath.formatPoints(offer.reward),
                                    }),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardBox(BuildContext context, Offer offer, Color accent) {
    final AppLocalizations l = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _stat(
            l.t('reward'),
            '+${PointsMath.formatPoints(offer.reward)} pts',
            accent,
          ),
          Container(width: 1, height: 34, color: accent.withValues(alpha: 0.3)),
          _stat(
            l.t('value'),
            PointsMath.formatCash(PointsMath.pointsToCash(offer.reward)),
            accent,
          ),
          Container(width: 1, height: 34, color: accent.withValues(alpha: 0.3)),
          _stat(l.t('category'), offer.category, accent),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: theme.colorScheme.brightness == Brightness.dark
                ? AppColors.brandAccent
                : accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _step(String n, String text) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brandAccent,
              shape: BoxShape.circle,
            ),
            child: Text(
              n,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF04121F),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
