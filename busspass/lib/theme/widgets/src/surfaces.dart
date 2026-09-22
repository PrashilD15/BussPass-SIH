/// Surfaces: [AppCard] and [AppBanner].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// A bordered surface. The default container for grouped content. Carries a
/// whisper of vertical sheen so every card reads as a softly-lifted panel,
/// never a flat slab.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? color;
  final Color? borderColor;

  /// Lift the card off the canvas with a shadow. Use for genuinely floating
  /// content, not as general decoration.
  final bool raised;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderRadius = AppSpacing.brLg,
    this.color,
    this.borderColor,
    this.raised = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final baseColor = color ?? palette.surface;
    final sheen = context.isDark
        ? Color.lerp(baseColor, Colors.white, 0.035)!
        : Color.lerp(baseColor, Colors.white, 0.55)!;
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        // A faint top-to-bottom sheen adds depth without decoration.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            sheen,
            baseColor,
          ],
          stops: const [0.0, 0.6],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.hairline),
        boxShadow: raised
            ? AppShadow.raised(Colors.black)
            : AppShadow.card(Colors.black),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    return onTap == null
        ? gradient
        : Material(
            color: Colors.transparent,
            borderRadius: borderRadius,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap!();
              },
              borderRadius: borderRadius,
              overlayColor: WidgetStatePropertyAll(
                palette.brand.withValues(alpha: 0.06),
              ),
              child: gradient,
            ),
          );
  }
}

/// A tinted panel used to carry a status message inline.
class AppBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final AppBannerTone tone;
  final Widget? action;

  const AppBanner({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = AppBannerTone.info,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (fg, bg) = switch (tone) {
      AppBannerTone.info => (palette.info, palette.infoLight),
      AppBannerTone.success => (palette.success, palette.successLight),
      AppBannerTone.warning => (palette.warning, palette.warningLight),
      AppBannerTone.danger => (palette.danger, palette.dangerLight),
      AppBannerTone.brand => (palette.brandDeep, palette.brandLight),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.brMd,
        border: Border.all(color: fg.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: fg),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: fg.withValues(alpha: 0.88)),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

enum AppBannerTone { info, success, warning, danger, brand }
