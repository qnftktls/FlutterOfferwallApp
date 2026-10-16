import 'package:flutter/material.dart';

import '../models/offer.dart';
import '../services/offerwall_controller.dart';
import '../theme/app_theme.dart';

/// Flutter Web fallback for the offerwall.
///
/// `webview_flutter` has no web implementation, so on the web preview we render
/// a styled, in-app offer list that exercises the exact same bridge logic the
/// real WebView uses. This keeps the preview meaningful and the bridge testable
/// without a device.
class OfferwallView extends StatefulWidget {
  const OfferwallView({
    super.key,
    required this.controller,
    this.onPageError,
    this.onExternalLink,
  });

  final OfferwallController controller;
  final ValueChanged<String>? onPageError;
  final ValueChanged<String>? onExternalLink;

  @override
  State<OfferwallView> createState() => _OfferwallViewState();
}

class _OfferwallViewState extends State<OfferwallView> {
  static const List<Offer> _offers = <Offer>[
    Offer(
      id: '1001',
      title: 'Try a featured game',
      subtitle: 'Playtime · Reach level 5 · ~3 min',
      reward: 250,
      accent: '#00B37E',
      iconEmoji: '🎮',
    ),
    Offer(
      id: '1002',
      title: 'Quick opinion survey',
      subtitle: 'SurveyX · 5 questions · ~2 min',
      reward: 120,
      accent: '#3B82F6',
      iconEmoji: '📋',
    ),
    Offer(
      id: '1003',
      title: 'Install & open app',
      subtitle: 'ShopBack · First launch only',
      reward: 80,
      accent: '#F59E0B',
      iconEmoji: '📱',
    ),
    Offer(
      id: '1004',
      title: 'Start a free trial',
      subtitle: 'FitLoop · No card required',
      reward: 400,
      accent: '#8B5CF6',
      iconEmoji: '🏃',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          children: <Widget>[
            _hero(context),
            const SizedBox(height: AppSpacing.md),
            ..._offers.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
                child: _OfferCard(offer: o, onTap: () => _complete(o)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Web preview fallback — the real app renders your provider\'s '
              'offerwall in a native WebView with the same JS bridge.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Earn Rewards',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Complete offers to top up your balance',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Web preview',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  void _complete(Offer offer) {
    // Route through the controller so the same logic as the native bridge runs.
    widget.controller.handleMessage(
      '{"type":"offerCompleted","offerId":"${offer.id}",'
      '"reward":${offer.reward},"signature":""}',
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = _hex(offer.accent);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  offer.iconEmoji ?? offer.title.characters.first,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      offer.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '+${offer.reward}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.brightness == Brightness.dark
                          ? AppColors.brandAccent
                          : accent,
                    ),
                  ),
                  Text('pts', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _hex(String hex) {
    final String cleaned = hex.replaceAll('#', '');
    final int value = int.tryParse(cleaned, radix: 16) ?? 0x00B37E;
    return Color(0xFF000000 | value);
  }
}
