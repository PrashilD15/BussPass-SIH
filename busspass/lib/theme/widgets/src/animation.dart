/// Animation helpers.
///
/// Centralised so every screen animates identically and no screen invents its
/// own delay ladder.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:busspass/theme/app_theme.dart';

/// Staggered entrance for a list of children.
extension StaggerAnimation on Widget {
  /// Global switch wired to the rider's "reduce motion" setting. When false,
  /// [staggerIn] and [fadeInUp] return the child untouched — motion-sensitive
  /// users get content without any entrance animation, everywhere at once.
  static bool enabled = true;

  Widget staggerIn(int index, {Duration? delay}) {
    if (!enabled) return this;
    return animate(delay: delay ?? (AppMotion.stagger * index))
        .fadeIn(duration: AppMotion.normal, curve: AppMotion.enter)
        .slideY(begin: 0.08, end: 0, curve: AppMotion.enter);
  }

  Widget fadeInUp({Duration? delay}) {
    if (!enabled) return this;
    return animate(delay: delay ?? Duration.zero)
        .fadeIn(duration: AppMotion.normal, curve: AppMotion.enter)
        .slideY(begin: 0.06, end: 0, curve: AppMotion.enter);
  }
}
