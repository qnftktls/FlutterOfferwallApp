import 'package:flutter/material.dart';

/// Flutter Web fallback for the AdMob banner.
///
/// `google_mobile_ads` supports Android / iOS only, so on the web preview we show
/// a clearly-labelled placeholder of the same height, keeping the layout honest.
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key, this.height = 50});

  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: height,
      alignment: Alignment.center,
      color: theme.cardTheme.color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.campaign_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Text(
            'AdMob banner (test id) — mobile only',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
