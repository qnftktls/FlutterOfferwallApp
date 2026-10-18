import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/main_shell.dart';
import 'services/ads_init.dart';
import 'services/points_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the persisted points balance + history before the first frame.
  await PointsRepository.instance.load();

  // Initialize the Google Mobile Ads SDK (no-op on Flutter Web).
  await initAds();

  runApp(const RewardsHubApp());
}

/// Rewards Hub — a Freecash-style rewards app (AdMob banner + WebView offerwall).
///
/// One Flutter codebase for Android + iOS (with a Flutter Web preview).
class RewardsHubApp extends StatelessWidget {
  const RewardsHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PointsRepository>.value(
      value: PointsRepository.instance,
      child: MaterialApp(
        title: 'Rewards Hub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const MainShell(),
      ),
    );
  }
}
