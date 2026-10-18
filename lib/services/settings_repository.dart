import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Persists and exposes app-wide settings (currently the UI language).
///
/// Kept separate from [PointsRepository] so concerns stay separated; both are
/// injected with `provider` in `main.dart`.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository._();

  static final SettingsRepository instance = SettingsRepository._();

  static const String _localeKey = 'settings.locale.v1';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  SharedPreferences? _prefs;

  /// Loads the saved locale (or auto-detects on first run).
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final String? code = _prefs?.getString(_localeKey);
      if (code != null) {
        _locale = Locale(code);
      } else {
        // First launch: match the device language if we support it.
        final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
        _locale = kSupportedLocales.any(
          (l) => l.languageCode == device.languageCode,
        )
            ? Locale(device.languageCode)
            : const Locale('en');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SettingsRepository.load failed: $e');
    }
    notifyListeners();
  }

  /// Switches the UI language and persists the choice.
  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    try {
      await _prefs?.setString(_localeKey, locale.languageCode);
    } catch (e) {
      if (kDebugMode) debugPrint('SettingsRepository.persist failed: $e');
    }
  }

  void toggleLocale() {
    setLocale(Locale(_locale.languageCode == 'ko' ? 'en' : 'ko'));
  }
}
