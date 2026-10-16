import 'package:flutter/material.dart';

/// Central design tokens for Rewards Hub.
///
/// Ported 1:1 from the native app's `res/values/colors.xml` +
/// `res/values-night/colors.xml`, so the Flutter build keeps the same
/// fintech look: deep-navy ink on clean surfaces with a mint "credit" accent.
class AppColors {
  AppColors._();

  // Brand (shared across light & dark)
  static const Color brandPrimary = Color(0xFF0A2540); // deep navy
  static const Color brandAccent = Color(0xFF00B37E); // mint / credit green
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Light palette
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFF4F7FB);
  static const Color lightOnSurface = Color(0xFF0A2540);
  static const Color lightOnSurfaceMuted = Color(0xFF5B6B7C);
  static const Color lightDivider = Color(0xFFE6EAF0);

  // Dark palette
  static const Color darkSurface = Color(0xFF0B1220);
  static const Color darkSurfaceRaised = Color(0xFF111A2B);
  static const Color darkOnSurface = Color(0xFFE7ECF3);
  static const Color darkOnSurfaceMuted = Color(0xFF9AA7B8);
  static const Color darkDivider = Color(0xFF1E2A3E);
}

/// Spacing scale (mirrors `res/values/dimens.xml`).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Builds the [ThemeData] for light and dark mode (Material 3).
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
    brightness: Brightness.light,
    surface: AppColors.lightSurface,
    surfaceRaised: AppColors.lightSurfaceRaised,
    onSurface: AppColors.lightOnSurface,
    onSurfaceMuted: AppColors.lightOnSurfaceMuted,
    divider: AppColors.lightDivider,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    surface: AppColors.darkSurface,
    surfaceRaised: AppColors.darkSurfaceRaised,
    onSurface: AppColors.darkOnSurface,
    onSurfaceMuted: AppColors.darkOnSurfaceMuted,
    divider: AppColors.darkDivider,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color surfaceRaised,
    required Color onSurface,
    required Color onSurfaceMuted,
    required Color divider,
  }) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brandPrimary,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? AppColors.brandAccent : AppColors.brandPrimary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.brandAccent,
          surface: surface,
          onSurface: onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(onSurface, onSurfaceMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandAccent,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandAccent,
      ),
    );
  }

  static TextTheme _textTheme(Color onSurface, Color muted) {
    return TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: onSurface),
      bodySmall: TextStyle(fontSize: 13, height: 1.4, color: muted),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    );
  }

  /// Exposes a muted-text colour derived from brightness for occasional use.
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.darkOnSurfaceMuted
      : AppColors.lightOnSurfaceMuted;
}
