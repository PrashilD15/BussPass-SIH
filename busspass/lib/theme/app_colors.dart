/// The BussPass colour system.
///
/// Built as **semantic roles**, not a flat list of hex codes, and resolved per
/// brightness. A widget asks for `context.palette.surfaceRaised`, never for a
/// literal colour, which is what makes a genuine dark mode possible rather than
/// an inverted approximation.
///
/// LIGHT — "Saffron Dawn"
///   Warm sandy parchment canvas, petrol-teal brand, saffron-gold accent.
///   Inspired by Indian morning light — warm, natural, never clinical.
///
/// DARK — "Midnight Indigo"
///   Deep indigo-slate surfaces (not flat black), luminous aqua-mint brand,
///   warm amber accent. Easy on the eyes during night-time journeys.
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

  // ─────────────────────────────────────────────────────────────────────────
  // LIGHT — "Saffron Dawn"
  // Canvas:  warm sandy parchment  (HSL 40°  20%  95%)
  // Brand:   petrol teal           (HSL 176° 67%  32%)  — calm deep river
  // Accent:  saffron gold          (HSL 37°  72%  46%)  — warm pop, not loud
  // Ink:     warm charcoal         (HSL 225° 22%  16%)  — no cold blue-black
  // ─────────────────────────────────────────────────────────────────────────
  static const AppPalette light = AppPalette(
    ink:       Color(0xFF1E2433),
    inkSoft:   Color(0xFF485068),
    inkMuted:  Color(0xFF7C8399),
    inkFaint:  Color(0xFFB0B6C8),
    brand:      Color(0xFF1B8A80),
    brandDeep:  Color(0xFF136B62),
    brandLight: Color(0xFFD4EFEC),
    onBrand:    Color(0xFFFFFFFF),
    canvas:       Color(0xFFF5F3EE),
    surface:      Color(0xFFFEFCF8),
    surfaceAlt:   Color(0xFFF0EDE5),
    surfaceRaised:Color(0xFFFFFDF9),
    hairline:      Color(0xFFE2DDD3),
    hairlineStrong:Color(0xFFCBC5B8),
    accent:      Color(0xFFCA8A24),
    accentLight: Color(0xFFFFF1D6),
    success:      Color(0xFF287D5E),
    successLight: Color(0xFFDBF2EA),
    warning:      Color(0xFFB07320),
    warningLight: Color(0xFFFFF0D4),
    danger:       Color(0xFFC0402A),
    dangerLight:  Color(0xFFFFEAE5),
    info:         Color(0xFF3568A8),
    infoLight:    Color(0xFFDDE9F8),
    routeLine:      Color(0xFF1B8A80),
    routeTravelled: Color(0xFFB0B6C8),
    liveBus:        Color(0xFFCA8A24),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // DARK — "Midnight Indigo"
  // Canvas:  deep indigo-slate     (HSL 228° 23%  10%)  — not flat black
  // Brand:   luminous aqua-mint    (HSL 175° 54%  51%)  — glows without neon
  // Accent:  soft amber gold       (HSL 38°  80%  57%)  — warm, easy on eyes
  // Ink:     cool lavender-white   (HSL 228° 28%  93%)  — no harsh contrast
  // ─────────────────────────────────────────────────────────────────────────
  static const AppPalette dark = AppPalette(
    ink:       Color(0xFFE6E8F2),
    inkSoft:   Color(0xFFADB3CC),
    inkMuted:  Color(0xFF787F9A),
    inkFaint:  Color(0xFF4C526E),
    brand:      Color(0xFF40C4B8),
    brandDeep:  Color(0xFF5DD8CC),
    brandLight: Color(0xFF0D2E2C),
    onBrand:    Color(0xFF051918),
    canvas:       Color(0xFF10121A),
    surface:      Color(0xFF181C28),
    surfaceAlt:   Color(0xFF1D2235),
    surfaceRaised:Color(0xFF23293E),
    hairline:      Color(0xFF282E45),
    hairlineStrong:Color(0xFF3A4266),
    accent:      Color(0xFFE8A83A),
    accentLight: Color(0xFF2C1E02),
    success:      Color(0xFF4DC898),
    successLight: Color(0xFF092214),
    warning:      Color(0xFFE8A83A),
    warningLight: Color(0xFF281A02),
    danger:       Color(0xFFEA7B6A),
    dangerLight:  Color(0xFF2A0C08),
    info:         Color(0xFF82AEED),
    infoLight:    Color(0xFF0B182E),
    routeLine:      Color(0xFF40C4B8),
    routeTravelled: Color(0xFF4C526E),
    liveBus:        Color(0xFFE8A83A),
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

  static const Color ink        = Color(0xFF1E2433);
  static const Color inkSoft    = Color(0xFF485068);
  static const Color inkMuted   = Color(0xFF7C8399);
  static const Color brand      = Color(0xFF1B8A80);
  static const Color brandDeep  = Color(0xFF136B62);
  static const Color brandLight = Color(0xFFD4EFEC);
  static const Color canvas     = Color(0xFFF5F3EE);
  static const Color surface    = Color(0xFFFEFCF8);
  static const Color surfaceAlt = Color(0xFFF0EDE5);
  static const Color hairline   = Color(0xFFE2DDD3);
  static const Color accent     = Color(0xFFCA8A24);
  static const Color danger     = Color(0xFFC0402A);

  static Color onBrand() => Colors.white;
  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);
}
