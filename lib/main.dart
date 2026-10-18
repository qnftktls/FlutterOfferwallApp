import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/main_shell.dart';
import 'services/ads_init.dart';
import 'services/auth_service.dart';
import 'services/points_repository.dart';
import 'services/reward_service.dart';
import 'services/settings_repository.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (Auth + Firestore + Functions). Degrades gracefully if it fails.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AuthService.instance.markReady(true);
    SyncService.instance.markReady(true);
    RewardService.instance.markReady(true);
    AuthService.instance.bind();
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init failed (continuing offline): $e');
    AuthService.instance.markReady(false);
    SyncService.instance.markReady(false);
    RewardService.instance.markReady(false);
  }

  // Load persisted state before the first frame.
  await SettingsRepository.instance.load();
  await PointsRepository.instance.load();

  // Initialize the Google Mobile Ads SDK (no-op on Flutter Web).
  await initAds();

  runApp(const RewardsHubApp());
}

/// Rewards Hub — a Freecash-style rewards app (AdMob + WebView offerwall).
///
/// One Flutter codebase for Android + iOS (with a Flutter Web preview).
class RewardsHubApp extends StatelessWidget {
  const RewardsHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PointsRepository>.value(
          value: PointsRepository.instance,
        ),
        ChangeNotifierProvider<SettingsRepository>.value(
          value: SettingsRepository.instance,
        ),
      ],
      child: Consumer<SettingsRepository>(
        builder: (BuildContext context, SettingsRepository settings, _) {
          return MaterialApp(
            title: 'Rewards Hub',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,
            locale: settings.locale,
            supportedLocales: kSupportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MainShell(),
          );
        },
      ),
    );
  }
}
