import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Design tokens — spacing and radius shared across every screen so the
/// layout stays disciplined (no arbitrary 13px gaps or mismatched corners).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
}

/// The application theme.
///
/// Material 3 is used as the skeleton but every semantic colour is remapped
/// to the BussPass palette so widgets (buttons, inputs, progress) inherit
/// consistent styling without needing repeated overrides.
ThemeData buildAppTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
    surface: AppColors.surface,
  );

  final scheme = baseScheme.copyWith(
    primary: AppColors.brand,
    onPrimary: AppColors.onBrand(),
    primaryContainer: AppColors.brandLight,
    onPrimaryContainer: AppColors.brandDeep,
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairline,
    error: AppColors.danger,
  );

  final baseTextTheme = GoogleFonts.interTextTheme();
  final textTheme = baseTextTheme.copyWith(
    displaySmall: baseTextTheme.displaySmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
    ),
    headlineLarge: baseTextTheme.headlineLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    ),
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      color: AppColors.inkSoft,
    ),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
    ),
  );

  final buttonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.brand,
      foregroundColor: AppColors.onBrand(),
      elevation: 0,
      minimumSize: const Size.fromHeight(54),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: textTheme,
    elevatedButtonTheme: buttonTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 18),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brand
            : Colors.transparent,
      ),
    ),
  );
}
