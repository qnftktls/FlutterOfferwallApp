import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/offerwall_controller.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad.dart';
import '../widgets/offerwall_view.dart';
import '../widgets/rewards_header.dart';

/// The hybrid monetization main screen:
///   header (balance)  ->  offerwall  ->  bottom AdMob banner.
///
/// Ported from the native `MainActivity` + `activity_main.xml`.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final OfferwallController _offerwall;

  @override
  void initState() {
    super.initState();
    _offerwall = OfferwallController();
    _offerwall.addListener(_onOfferwallMessage);
  }

  @override
  void dispose() {
    _offerwall.removeListener(_onOfferwallMessage);
    _offerwall.dispose();
    super.dispose();
  }

  /// Surface reward feedback as a snack bar (mirrors the native Toast).
  void _onOfferwallMessage() {
    final String? message = _offerwall.lastMessage;
    if (message == null || !mounted) return;
    _offerwall.lastMessage = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandAccent,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // 1. HEADER — app name + live balance
            RewardsHeader(onTapBalance: () => _showResetDialog()),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),

            // 2. CENTER — offerwall (WebView on mobile, Flutter fallback on web)
            Expanded(
              child: OfferwallView(
                controller: _offerwall,
                onPageError: _showError,
                onExternalLink: _onExternalLink,
              ),
            ),

            // 3. BOTTOM — AdMob banner (test id today; swap in AdIds before release)
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Divider(height: 1, thickness: 1, color: theme.dividerColor),
                  const BannerAdWidget(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onExternalLink(String url) {
    // The native build opened external links in the system browser; the offerwall
    // view already prevents in-app navigation, so we surface it to the user.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('External link blocked: $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showResetDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reset balance?'),
        content: const Text(
          'This clears your points and reward history. Useful for testing.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<PointsRepository>().reset();
    }
  }
}
