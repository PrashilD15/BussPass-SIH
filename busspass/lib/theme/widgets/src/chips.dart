/// Chips and badges: [TagChip], [LivePulse].
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

import 'surfaces.dart' show AppBannerTone;

/// A compact pill label.
class TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? foreground;
  final Color? background;
  final bool dense;

  const TagChip({
    super.key,
    required this.label,
    this.icon,
    this.foreground,
    this.background,
    this.dense = false,
  });

  /// A chip themed for a semantic tone.
  factory TagChip.tone(
    BuildContext context,
    String label, {
    IconData? icon,
    required AppBannerTone tone,
    bool dense = false,
  }) {
    final palette = context.palette;
    final (fg, bg) = switch (tone) {
      AppBannerTone.info => (palette.info, palette.infoLight),
      AppBannerTone.success => (palette.success, palette.successLight),
      AppBannerTone.warning => (palette.warning, palette.warningLight),
      AppBannerTone.danger => (palette.danger, palette.dangerLight),
      AppBannerTone.brand => (palette.brandDeep, palette.brandLight),
    };
    return TagChip(
      label: label,
      icon: icon,
      foreground: fg,
      background: bg,
      dense: dense,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = foreground ?? palette.brandDeep;
    final bg = background ?? palette.brandLight;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? AppSpacing.xxs : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppSpacing.brPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontSize: dense ? 10.5 : 11.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// A live-data indicator with a breathing pulse.
///
/// The pulse is meaningful here: it marks data that is genuinely arriving. The
/// old code pulsed a "Live Sync" badge over entirely hardcoded values.
class LivePulse extends StatelessWidget {
  final String label;
  final bool active;

  const LivePulse({super.key, this.label = 'Live', this.active = true});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.success : palette.inkMuted;

    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active)
          dot
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 700.ms)
              .then()
              .fadeOut(duration: 700.ms)
        else
          dot,
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
