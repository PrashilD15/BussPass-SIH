/// Theme construction and layout tokens.
///
/// Both brightnesses are built from the same [AppPalette] role set, so a screen
/// written once renders correctly in either. Every component theme that the app
/// actually uses is defined here — inputs, cards, sheets, snackbars, chips,
/// buttons — rather than being hand-rolled per screen, which is how the old code
/// ended up with four different input border styles and an invisible button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Spacing, radius, and elevation tokens.
///
/// A closed set, so layouts cannot drift into arbitrary 13px gaps and mismatched
/// corners.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double radiusXs = 6;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  /// Minimum tappable dimension. Below 48dp a target fails accessibility
  /// guidance on both platforms.
  static const double minTouchTarget = 48;

  /// Standard control height, used by buttons and inputs so they align.
  static const double controlHeight = 54;

  /// Horizontal page inset.
  static const double pageInset = 20;

  static const BorderRadius brXs =
      BorderRadius.all(Radius.circular(radiusXs));
  static const BorderRadius brSm =
      BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius brMd =
      BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius brLg =
      BorderRadius.all(Radius.circular(radiusLg));
  static const BorderRadius brXl =
      BorderRadius.all(Radius.circular(radiusXl));
  static const BorderRadius brPill =
      BorderRadius.all(Radius.circular(radiusPill));
}

/// Motion tokens.
///
/// Durations are deliberately short. Transit apps are used in a hurry, often
/// one-handed at a bus stand; animation should confirm an action, never delay it.
class AppMotion {
  AppMotion._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasis = Curves.easeOutBack;

  /// Stagger step for list entrance animations.
  static const Duration stagger = Duration(milliseconds: 45);
}

/// Elevation as a shadow list, since Material 3 tonal elevation reads muddy
/// against the warm paper palette.
class AppShadow {
  AppShadow._();

  static List<BoxShadow> card(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> raised(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> floating(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.14),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Build the light theme.
ThemeData buildLightTheme() => _build(AppPalette.light, Brightness.light);

/// Build the dark theme.
ThemeData buildDarkTheme() => _build(AppPalette.dark, Brightness.dark);

/// Retained for the existing `main.dart` call site.
ThemeData buildAppTheme() => buildLightTheme();

ThemeData _build(AppPalette palette, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.brand,
    onPrimary: palette.onBrand,
    primaryContainer: palette.brandLight,
    onPrimaryContainer: brightness == Brightness.light
        ? palette.brandDeep
        : palette.brand,
    secondary: palette.accent,
    onSecondary: brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF241A08),
    secondaryContainer: palette.accentLight,
    onSecondaryContainer: palette.accent,
    tertiary: palette.info,
    onTertiary: Colors.white,
    tertiaryContainer: palette.infoLight,
    onTertiaryContainer: palette.info,
    error: palette.danger,
    onError: Colors.white,
    errorContainer: palette.dangerLight,
    onErrorContainer: palette.danger,
    surface: palette.surface,
    onSurface: palette.ink,
    surfaceContainerLowest: palette.canvas,
    surfaceContainerLow: palette.surfaceAlt,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.surfaceAlt,
    surfaceContainerHighest: palette.surfaceRaised,
    onSurfaceVariant: palette.inkMuted,
    outline: palette.hairline,
    outlineVariant: palette.hairline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: palette.ink,
    onInverseSurface: palette.canvas,
    inversePrimary: palette.brandLight,
  );

  final base = GoogleFonts.interTextTheme();

  TextStyle style(
    TextStyle? from, {
    required double size,
    required FontWeight weight,
    double? spacing,
    double? height,
    Color? color,
  }) =>
      (from ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color ?? palette.ink,
      );

  final textTheme = base.copyWith(
    displayLarge: style(base.displayLarge,
        size: 40, weight: FontWeight.w800, spacing: -1.6, height: 1.1),
    displayMedium: style(base.displayMedium,
        size: 34, weight: FontWeight.w800, spacing: -1.3, height: 1.12),
    displaySmall: style(base.displaySmall,
        size: 30, weight: FontWeight.w800, spacing: -1.1, height: 1.15),
    headlineLarge: style(base.headlineLarge,
        size: 27, weight: FontWeight.w800, spacing: -0.8, height: 1.18),
    headlineMedium: style(base.headlineMedium,
        size: 23, weight: FontWeight.w700, spacing: -0.5, height: 1.2),
    headlineSmall: style(base.headlineSmall,
        size: 20, weight: FontWeight.w700, spacing: -0.3, height: 1.24),
    titleLarge: style(base.titleLarge,
        size: 18, weight: FontWeight.w700, spacing: -0.3, height: 1.28),
    titleMedium: style(base.titleMedium,
        size: 16, weight: FontWeight.w600, spacing: -0.1, height: 1.32),
    titleSmall: style(base.titleSmall,
        size: 14, weight: FontWeight.w600, height: 1.36),
    bodyLarge: style(base.bodyLarge,
        size: 16, weight: FontWeight.w400, height: 1.5),
    bodyMedium: style(base.bodyMedium,
        size: 14, weight: FontWeight.w400, height: 1.48, color: palette.inkSoft),
    bodySmall: style(base.bodySmall,
        size: 12.5,
        weight: FontWeight.w400,
        height: 1.44,
        color: palette.inkMuted),
    labelLarge: style(base.labelLarge,
        size: 14, weight: FontWeight.w600, spacing: 0.1),
    labelMedium: style(base.labelMedium,
        size: 12, weight: FontWeight.w600, spacing: 0.2,
        color: palette.inkMuted),
    labelSmall: style(base.labelSmall,
        size: 11, weight: FontWeight.w600, spacing: 0.4,
        color: palette.inkMuted),
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: AppSpacing.brMd,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.canvas,
    canvasColor: palette.canvas,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,

    extensions: <ThemeExtension<dynamic>>[palette],

    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      iconTheme: IconThemeData(color: palette.ink, size: 24),
    ),

    // Buttons derive foreground from the scheme, so a custom background can
    // never produce white-on-white — the bug that made the old Google sign-in
    // button invisible.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.brand,
        foregroundColor: palette.onBrand,
        disabledBackgroundColor: palette.hairline,
        disabledForegroundColor: palette.inkFaint,
        elevation: 0,
        minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.brand,
        foregroundColor: palette.onBrand,
        minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.hairlineStrong),
        minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.brand,
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brSm),
        textStyle: textTheme.labelLarge,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.inkSoft,
        minimumSize: const Size.square(AppSpacing.minTouchTarget),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: textTheme.bodyLarge?.copyWith(color: palette.inkFaint),
      labelStyle: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
      floatingLabelStyle: textTheme.labelMedium?.copyWith(color: palette.brand),
      helperStyle: textTheme.bodySmall,
      errorStyle: textTheme.bodySmall?.copyWith(color: palette.danger),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      border: inputBorder(palette.hairline),
      enabledBorder: inputBorder(palette.hairline),
      focusedBorder: inputBorder(palette.brand, 1.6),
      errorBorder: inputBorder(palette.danger),
      focusedErrorBorder: inputBorder(palette.danger, 1.6),
      disabledBorder: inputBorder(palette.hairline),
      prefixIconColor: palette.inkMuted,
      suffixIconColor: palette.inkMuted,
    ),

    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.brLg,
        side: BorderSide(color: palette.hairline),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: palette.hairline,
      thickness: 1,
      space: 1,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      selectedColor: palette.brandLight,
      disabledColor: palette.hairline,
      labelStyle: textTheme.labelMedium?.copyWith(color: palette.inkSoft),
      secondaryLabelStyle:
          textTheme.labelMedium?.copyWith(color: palette.brandDeep),
      side: BorderSide(color: palette.hairline),
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brPill),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.surfaceRaised,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      dragHandleColor: palette.hairlineStrong,
      showDragHandle: true,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brLg),
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyMedium,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.canvas),
      actionTextColor: palette.brandLight,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      elevation: 0,
    ),

    listTileTheme: ListTileThemeData(
      iconColor: palette.inkMuted,
      textColor: palette.ink,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall,
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      minVerticalPadding: AppSpacing.md,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.onBrand
              : palette.surface),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.brand
              : palette.hairlineStrong),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.brand
              : palette.hairlineStrong),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.brand
              : Colors.transparent),
      checkColor: WidgetStatePropertyAll(palette.onBrand),
      side: BorderSide(color: palette.hairlineStrong, width: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brXs),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.brand
              : palette.hairlineStrong),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: palette.brand,
      inactiveTrackColor: palette.hairline,
      thumbColor: palette.brand,
      overlayColor: palette.brand.withValues(alpha: 0.12),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.brand,
      linearTrackColor: palette.hairline,
      circularTrackColor: palette.hairline,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: palette.brand,
      unselectedLabelColor: palette.inkMuted,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: palette.brand,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: palette.hairline,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.ink,
        borderRadius: AppSpacing.brSm,
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: palette.canvas),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.surfaceRaised,
      foregroundColor: palette.brand,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? palette.brandLight
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? palette.brandDeep
                : palette.inkMuted),
        side: WidgetStatePropertyAll(BorderSide(color: palette.hairline)),
        textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.brMd,
        side: BorderSide(color: palette.hairline),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(color: palette.ink),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.brandLight,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
