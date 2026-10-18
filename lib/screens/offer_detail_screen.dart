import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/interstitial.dart';
import '../services/points_repository.dart';
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

  void _completeOffer() {
    if (_completed) return;
    final PointsRepository repo = context.read<PointsRepository>();
    repo.addPoints(
      widget.offer.reward,
      offerTitle: widget.offer.title,
      offerId: widget.offer.id,
    );
    setState(() => _completed = true);
    SnackBarHelper.showReward(
      context,
      'You earned ${PointsMath.formatPoints(widget.offer.reward)} points!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Offer offer = widget.offer;
    final Color accent = hexColor(offer.accent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offer details'),
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
                const SectionHeader(title: 'How to complete'),
                _step('1', 'Tap "Start offer" to open the provider page.'),
                _step('2', 'Follow the instructions (install, survey, etc.).'),
                _step('3', 'Come back here — your points are credited.'),
                const SizedBox(height: AppSpacing.md),
                const SectionHeader(title: 'Terms'),
                Text(
                  'Rewards are credited after the provider confirms completion. '
                  'In this demo the credit is applied locally and instantly. '
                  'In production this must be verified server-side.',
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
                      onPressed: _completed ? null : _completeOffer,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: _completed
                            ? theme.dividerColor
                            : AppColors.brandAccent,
                        foregroundColor: const Color(0xFF04121F),
                      ),
                      child: Text(
                        _completed
                            ? 'Completed ✓'
                            : 'Start offer · +${PointsMath.formatPoints(offer.reward)} pts',
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
            'Reward',
            '+${PointsMath.formatPoints(offer.reward)} pts',
            accent,
          ),
          Container(width: 1, height: 34, color: accent.withValues(alpha: 0.3)),
          _stat(
            'Value',
            PointsMath.formatCash(PointsMath.pointsToCash(offer.reward)),
            accent,
          ),
          Container(width: 1, height: 34, color: accent.withValues(alpha: 0.3)),
          _stat('Category', offer.category, accent),
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
