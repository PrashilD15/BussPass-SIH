/// The BussPass colour system.
///
/// Built as **semantic roles**, not a flat list of hex codes, and resolved per
/// brightness. A widget asks for `context.palette.surfaceRaised`, never for a
/// literal colour, which is what makes a genuine dark mode possible rather than
/// an inverted approximation.
///
/// Four layers:
///  - `ink`     — text and structure, from strongest to faintest
///  - `brand`   — a civic emerald-teal used for identity and primary action
///  - `paper`   — warm, low-blue neutrals so the UI reads as printed, not plastic
///  - `signal`  — status colours: fare accent, success, warning, danger, info
///
/// The dark palette is not the light one inverted. Dark surfaces are lifted with
/// a green-shifted charcoal so the brand still belongs, brand colours are
/// desaturated and brightened to hold contrast on dark, and the accent is warmed
/// further because saturated amber reads harsher on black.
library;

import 'package:flutter/material.dart';

/// Semantic colour roles, resolved for one brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  // ── Ink ────────────────────────────────────────────────────────────────
  /// Headings and primary body text.
  final Color ink;

  /// Secondary text — supporting copy, descriptions.
  final Color inkSoft;

  /// Tertiary text — labels, captions, metadata.
  final Color inkMuted;

  /// Faintest text — disabled states, placeholder text.
  final Color inkFaint;

  // ── Brand ──────────────────────────────────────────────────────────────
  /// Primary action and identity.
  final Color brand;

  /// Pressed and emphasis variant.
  final Color brandDeep;

  /// Tinted background for brand-adjacent surfaces.
  final Color brandLight;

  /// Text and icons on top of [brand].
  final Color onBrand;

  // ── Paper ──────────────────────────────────────────────────────────────
  /// The page background.
  final Color canvas;

  /// A card or sheet sitting on the canvas.
  final Color surface;

  /// A subtly differentiated surface — inset rows, secondary panels.
  final Color surfaceAlt;

  /// A surface lifted above others — bottom sheets, dialogs, floating bars.
  final Color surfaceRaised;

  /// Hairline borders and dividers.
  final Color hairline;

  /// A stronger border, for focused or selected outlines.
  final Color hairlineStrong;

  // ── Signal ─────────────────────────────────────────────────────────────
  /// Fare and monetary emphasis.
  final Color accent;

  /// Background tint for [accent].
  final Color accentLight;

  /// On-time, confirmed, seats available.
  final Color success;
  final Color successLight;

  /// Delayed, crowded, tight connection.
  final Color warning;
  final Color warningLight;

  /// Cancelled, error, SOS.
  final Color danger;
  final Color dangerLight;

  /// Neutral informational emphasis.
  final Color info;
  final Color infoLight;

  // ── Map ────────────────────────────────────────────────────────────────
  /// The route polyline.
  final Color routeLine;

  /// The already-travelled portion of a route.
  final Color routeTravelled;

  /// Live bus marker fill.
  final Color liveBus;

  const AppPalette({
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.inkFaint,
    required this.brand,
    required this.brandDeep,
    required this.brandLight,
    required this.onBrand,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.hairline,
    required this.hairlineStrong,
    required this.accent,
    required this.accentLight,
    required this.success,
    required this.successLight,
    required this.warning,
    required this.warningLight,
    required this.danger,
    required this.dangerLight,
    required this.info,
    required this.infoLight,
    required this.routeLine,
    required this.routeTravelled,
    required this.liveBus,
  });

  /// Light palette — warm paper, deep ink, emerald brand.
  static const AppPalette light = AppPalette(
    ink: Color(0xFF11151C),
    inkSoft: Color(0xFF3A424E),
    inkMuted: Color(0xFF6B7280),
    inkFaint: Color(0xFF9CA3AF),
    brand: Color(0xFF0E6B5C),
    brandDeep: Color(0xFF0A4E43),
    brandLight: Color(0xFFDFF0EA),
    onBrand: Color(0xFFFFFFFF),
    canvas: Color(0xFFF6F5F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFBFAF7),
    surfaceRaised: Color(0xFFFFFFFF),
    hairline: Color(0xFFE7E4DC),
    hairlineStrong: Color(0xFFD3CFC4),
    accent: Color(0xFFB4741A),
    accentLight: Color(0xFFFDF2DF),
    success: Color(0xFF1B7A54),
    successLight: Color(0xFFE2F3EB),
    warning: Color(0xFF9A6212),
    warningLight: Color(0xFFFCF0DA),
    danger: Color(0xFFB03A24),
    dangerLight: Color(0xFFFBE9E5),
    info: Color(0xFF2A5D8F),
    infoLight: Color(0xFFE6EFF8),
    routeLine: Color(0xFF0E6B5C),
    routeTravelled: Color(0xFF9CA3AF),
    liveBus: Color(0xFFB4741A),
  );

  /// Dark palette — green-shifted charcoal, brightened brand.
  ///
  /// Brand colours are lifted and desaturated: `#0E6B5C` on a near-black
  /// surface fails contrast for text, so the dark brand is `#4FBFA5`, which
  /// clears 4.5:1 against every dark surface here.
  static const AppPalette dark = AppPalette(
    ink: Color(0xFFF2F4F3),
    inkSoft: Color(0xFFC3CAC8),
    inkMuted: Color(0xFF929B99),
    inkFaint: Color(0xFF6B7472),
    brand: Color(0xFF4FBFA5),
    brandDeep: Color(0xFF6FD3BA),
    brandLight: Color(0xFF15332E),
    onBrand: Color(0xFF05201B),
    canvas: Color(0xFF0D1211),
    surface: Color(0xFF161C1B),
    surfaceAlt: Color(0xFF1D2423),
    surfaceRaised: Color(0xFF222A28),
    hairline: Color(0xFF2B3432),
    hairlineStrong: Color(0xFF3C4644),
    accent: Color(0xFFE8B563),
    accentLight: Color(0xFF33270F),
    success: Color(0xFF56C793),
    successLight: Color(0xFF11301F),
    warning: Color(0xFFE0AE5C),
    warningLight: Color(0xFF31250F),
    danger: Color(0xFFE8806A),
    dangerLight: Color(0xFF361A14),
    info: Color(0xFF7FB2E0),
    infoLight: Color(0xFF122435),
    routeLine: Color(0xFF4FBFA5),
    routeTravelled: Color(0xFF4A5453),
    liveBus: Color(0xFFE8B563),
  );

  /// A translucent black scrim, for overlays on imagery and maps.
  Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);

  /// Colour for a crowd level, drawn from the signal ramp.
  Color forCrowdLevel(int levelIndex) => switch (levelIndex) {
        0 => success,
        1 => success,
        2 => warning,
        3 => warning,
        _ => danger,
      };

  /// Colour for a service tier: ordinary through premium.
  Color forServiceTier(int tier) => switch (tier) {
        >= 4 => info,
        3 => brand,
        2 => accent,
        _ => inkMuted,
      };

  @override
  AppPalette copyWith({
    Color? ink,
    Color? inkSoft,
    Color? inkMuted,
    Color? inkFaint,
    Color? brand,
    Color? brandDeep,
    Color? brandLight,
    Color? onBrand,
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceRaised,
    Color? hairline,
    Color? hairlineStrong,
    Color? accent,
    Color? accentLight,
    Color? success,
    Color? successLight,
    Color? warning,
    Color? warningLight,
    Color? danger,
    Color? dangerLight,
    Color? info,
    Color? infoLight,
    Color? routeLine,
    Color? routeTravelled,
    Color? liveBus,
  }) {
    return AppPalette(
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      brandLight: brandLight ?? this.brandLight,
      onBrand: onBrand ?? this.onBrand,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      success: success ?? this.success,
      successLight: successLight ?? this.successLight,
      warning: warning ?? this.warning,
      warningLight: warningLight ?? this.warningLight,
      danger: danger ?? this.danger,
      dangerLight: dangerLight ?? this.dangerLight,
      info: info ?? this.info,
      infoLight: infoLight ?? this.infoLight,
      routeLine: routeLine ?? this.routeLine,
      routeTravelled: routeTravelled ?? this.routeTravelled,
      liveBus: liveBus ?? this.liveBus,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      ink: mix(ink, other.ink),
      inkSoft: mix(inkSoft, other.inkSoft),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkFaint: mix(inkFaint, other.inkFaint),
      brand: mix(brand, other.brand),
      brandDeep: mix(brandDeep, other.brandDeep),
      brandLight: mix(brandLight, other.brandLight),
      onBrand: mix(onBrand, other.onBrand),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      hairline: mix(hairline, other.hairline),
      hairlineStrong: mix(hairlineStrong, other.hairlineStrong),
      accent: mix(accent, other.accent),
      accentLight: mix(accentLight, other.accentLight),
      success: mix(success, other.success),
      successLight: mix(successLight, other.successLight),
      warning: mix(warning, other.warning),
      warningLight: mix(warningLight, other.warningLight),
      danger: mix(danger, other.danger),
      dangerLight: mix(dangerLight, other.dangerLight),
      info: mix(info, other.info),
      infoLight: mix(infoLight, other.infoLight),
      routeLine: mix(routeLine, other.routeLine),
      routeTravelled: mix(routeTravelled, other.routeTravelled),
      liveBus: mix(liveBus, other.liveBus),
    );
  }
}

/// `context.palette` — the only sanctioned way to reach a colour.
extension PaletteAccess on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Legacy static access, retained so existing call sites keep compiling while
/// they migrate to `context.palette`. These always resolve to the light palette
/// and are therefore **not** dark-mode correct — prefer `context.palette`.
@Deprecated('Use context.palette so the colour resolves per brightness')
class AppColors {
  AppColors._();

  static const Color ink = Color(0xFF11151C);
  static const Color inkSoft = Color(0xFF3A424E);
  static const Color inkMuted = Color(0xFF6B7280);
  static const Color brand = Color(0xFF0E6B5C);
  static const Color brandDeep = Color(0xFF0A4E43);
  static const Color brandLight = Color(0xFFDFF0EA);
  static const Color canvas = Color(0xFFF6F5F1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFFBFAF7);
  static const Color hairline = Color(0xFFE7E4DC);
  static const Color accent = Color(0xFFB4741A);
  static const Color danger = Color(0xFFB03A24);

  static Color onBrand() => Colors.white;
  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);
}
