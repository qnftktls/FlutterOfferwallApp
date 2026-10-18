import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sample_data.dart';
import '../l10n/app_localizations.dart';
import '../models/offer.dart';
import '../services/offerwall_controller.dart';
import '../services/points_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/offer_card.dart';
import '../widgets/offerwall_view.dart';
import 'offer_detail_screen.dart';

/// The "Earn" tab: the provider offerwall (WebView on mobile, Flutter fallback
/// on web) plus a browse-able list of sample offers, Freecash-style.
class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key, this.onOpenGames});

  final VoidCallback? onOpenGames;

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> {
  final OfferwallController _offerwall = OfferwallController();
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _offerwall.addListener(_onBridgeMessage);
  }

  @override
  void dispose() {
    _offerwall.removeListener(_onBridgeMessage);
    _offerwall.dispose();
    super.dispose();
  }

  /// Reward feedback from the WebView bridge (native path).
  void _onBridgeMessage() {
    final String? message = _offerwall.lastMessage;
    if (message == null || !mounted) return;
    _offerwall.lastMessage = null;
    SnackBarHelper.showReward(context, message);
  }

  List<Offer> get _filtered {
    if (_filter == 'All') return SampleData.offers;
    return SampleData.offers.where((o) => o.category == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = context.l10n;
    final List<String> categories = <String>[
      'All',
      ...{...SampleData.offers.map((o) => o.category)},
    ];

    return CustomScrollView(
      slivers: <Widget>[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverToBoxAdapter(child: _topBanner(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(title: l.t('featured_offerwall')),
                SizedBox(
                  height: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: OfferwallView(
                        controller: _offerwall,
                        onPageError: (m) =>
                            SnackBarHelper.showError(context, m),
                        onExternalLink: (u) => SnackBarHelper.showError(
                          context,
                          l.f('link_blocked', <String, Object?>{'url': u}),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionHeader(
                  title: l.t('more_offers'),
                  trailing: Text(
                    l.f('n_available', <String, Object?>{
                      'n': _filtered.length,
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterPill(
                              label: c,
                              selected: _filter == c,
                              onTap: () => setState(() => _filter = c),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          sliver: SliverList.separated(
            itemCount: _filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final Offer offer = _filtered[index];
              return OfferCard(offer: offer, onTap: () => _openOffer(offer));
            },
          ),
        ),
      ],
    );
  }

  Widget _topBanner(BuildContext context) {
    final AppLocalizations l = context.l10n;
    final PointsRepository repo = context.watch<PointsRepository>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.brandPrimary, Color(0xFF14507F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.t('your_balance'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  repo.cashFormatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  l.f('points_value', <String, Object?>{
                    'pts': PointsMath.formatPoints(repo.points),
                  }),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: widget.onOpenGames,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: const Color(0xFF04121F),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.sports_esports_rounded, size: 18),
                  label: Text(l.t('play_games')),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text('💸', style: TextStyle(fontSize: 52)),
        ],
      ),
    );
  }

  void _openOffer(Offer offer) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OfferDetailScreen(offer: offer)),
    );
  }
}

/// Small helper so every screen shows consistent feedback.
class SnackBarHelper {
  SnackBarHelper._();

  static void showReward(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              const Icon(
                Icons.celebration_rounded,
                color: Color(0xFF04121F),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF04121F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandAccent,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
