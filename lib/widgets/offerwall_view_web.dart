import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/offer.dart';
import '../services/offerwall_controller.dart';
import '../theme/app_theme.dart';
import 'offer_card.dart';

/// Flutter Web fallback for the offerwall.
///
/// `webview_flutter` has no web implementation, so on the web preview we render
/// a styled, in-app offer list that routes taps through the exact same bridge
/// logic the real WebView uses. This keeps the preview meaningful and the bridge
/// testable without a device.
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
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Earn Rewards', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Tap an offer to complete it',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Web preview', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...SampleData.offers
              .take(4)
              .map(
                (Offer o) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OfferCard(offer: o, onTap: () => _complete(o)),
                ),
              ),
        ],
      ),
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
