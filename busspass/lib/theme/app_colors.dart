import 'package:flutter/material.dart';

/// Centralised colour palette for BussPass.
///
/// The system is built on four layers:
///  - `ink`: the primary text / structural colour (deep blue-black)
///  - `brand`: a civic, emerald-leaning teal used for identity + actions
///  - `paper`: warm, low-blue neutrals so the UI reads as printed, not plastic
///  - `signal`: a single warm accent (amber) used sparingly for fare/emphasis
///
/// Everything else derives from opacity of these anchors rather than a long
/// list of ad-hoc hex codes.
class AppColors {
  AppColors._();

  // ── Ink (structural + text) ─────────────────────────────────────────
  static const Color ink = Color(0xFF11151C);
  static const Color inkSoft = Color(0xFF3A424E);
  static const Color inkMuted = Color(0xFF6B7280);

  // ── Brand ───────────────────────────────────────────────────────────
  static const Color brand = Color(0xFF0E6B5C);
  static const Color brandDeep = Color(0xFF0A4E43);
  static const Color brandLight = Color(0xFFDFF0EA);

  // ── Paper (warm, low-blue neutrals) ─────────────────────────────────
  static const Color canvas = Color(0xFFF6F5F1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFFBFAF7);
  static const Color hairline = Color(0xFFE7E4DC);

  // ── Signal ──────────────────────────────────────────────────────────
  static const Color accent = Color(0xFFE8A33D);
  static const Color danger = Color(0xFFC4563D);

  // Semantic colour stems
  static Color onBrand() => Colors.white;
  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);
}
