/// The BussPass component library.
///
/// Every screen composes from these. The rule: a screen never reaches for a raw
/// `Container` with a hand-written `BoxDecoration`, and never hardcodes a colour.
/// That is what kept the old code consistent-looking in isolation but drifting
/// in aggregate — four input styles, five card corner radii, and an invisible
/// button.
///
/// Each component resolves colour through `context.palette`, so all of it works
/// in dark mode without a second implementation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Surfaces
// ─────────────────────────────────────────────────────────────────────────────

/// A bordered surface. The default container for grouped content.
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

    final content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.hairline),
        boxShadow: raised ? AppShadow.raised(Colors.black) : null,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: borderRadius,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
                borderRadius: borderRadius,
                child: content,
              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Text and headers
// ─────────────────────────────────────────────────────────────────────────────

/// A section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        // Only rendered when it actually does something — the old header showed
        // an "All" link wired to an empty callback.
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// A key-value statistic, as used in journey overview rows.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;

  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: palette.inkMuted),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chips and badges
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

/// The primary call to action.
///
/// Foreground colour is **derived** from the background rather than hardcoded,
/// which is what makes a light-background variant legible. The old
/// implementation hardcoded white text and produced an invisible button when
/// given a white background.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Trailing icon instead of leading.
  final bool iconTrailing;
  final bool loading;
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Render as an outline instead of a filled surface.
  final bool outlined;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconTrailing = false,
    this.loading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.outlined = false,
    this.expand = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  /// Pick a foreground that actually contrasts with the given background.
  ///
  /// Uses relative luminance rather than a hardcoded choice, so any background
  /// — brand, white, danger — yields legible content.
  Color _resolveForeground(Color background) {
    if (widget.foregroundColor != null) return widget.foregroundColor!;
    return background.computeLuminance() > 0.55
        ? context.palette.ink
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final background = widget.outlined
        ? Colors.transparent
        : (widget.backgroundColor ?? palette.brand);
    final foreground = widget.outlined
        ? (widget.foregroundColor ?? palette.ink)
        : _resolveForeground(background);

    final effectiveBackground =
        _enabled ? background : palette.hairline;
    final effectiveForeground =
        _enabled ? foreground : palette.inkFaint;

    final children = <Widget>[];
    if (widget.loading) {
      children.add(SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(effectiveForeground),
        ),
      ));
    } else {
      if (widget.icon != null && !widget.iconTrailing) {
        children.addAll([
          Icon(widget.icon, size: 19, color: effectiveForeground),
          const SizedBox(width: AppSpacing.sm + 2),
        ]);
      }
      children.add(Text(
        widget.label,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: effectiveForeground, fontSize: 15),
      ));
      if (widget.icon != null && widget.iconTrailing) {
        children.addAll([
          const SizedBox(width: AppSpacing.sm + 2),
          Icon(widget.icon, size: 19, color: effectiveForeground),
        ]);
      }
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) {
          HapticFeedback.lightImpact();
          setState(() => _pressed = true);
        } : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1.0,
          duration: AppMotion.instant,
          curve: AppMotion.enter,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: AppSpacing.controlHeight,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              color: effectiveBackground,
              borderRadius: AppSpacing.brMd,
              border: widget.outlined
                  ? Border.all(
                      color: _enabled
                          ? palette.hairlineStrong
                          : palette.hairline)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon action with a tinted background.
class IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;

  const IconAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = Material(
      color: background ?? palette.surface,
      borderRadius: AppSpacing.brMd,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: AppSpacing.brMd,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 21, color: color ?? palette.inkSoft),
        ),
      ),
    );

    final bordered = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppSpacing.brMd,
        border: Border.all(color: palette.hairline),
      ),
      child: button,
    );

    // A tooltip doubles as the accessibility label, so an icon-only control is
    // never unlabelled to a screen reader.
    return tooltip == null
        ? bordered
        : Tooltip(message: tooltip!, child: bordered);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────────────────────

/// An empty state with an optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: palette.hairline),
              ),
              child: Icon(icon, size: 32, color: palette.inkFaint),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error state that explains the failure and offers a retry.
///
/// Deliberately does not dump the raw exception at the user — the old auth
/// wrapper rendered `'Something went wrong!\n$error'` straight to the screen.
class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  /// The underlying error, shown only in debug builds.
  final Object? detail;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: palette.inkFaint),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.md),
              // Assertions are stripped in release, so this block only ever
              // renders in debug.
              Builder(builder: (context) {
                var showDetail = false;
                assert(() {
                  showDetail = true;
                  return true;
                }());
                if (!showDetail) return const SizedBox.shrink();
                return Text(
                  '$detail',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.inkFaint),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                );
              }),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder block, for loading states that have a known shape.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppSpacing.brSm,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.hairline,
        borderRadius: borderRadius,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 0.45, end: 1.0, duration: 800.ms);
  }
}

/// A skeleton shaped like a result card, so loading does not shift the layout.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(children: [
            SkeletonBox(width: 110, height: 20),
            Spacer(),
            SkeletonBox(width: 60, height: 20),
          ]),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 12),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 200, height: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout helpers
// ─────────────────────────────────────────────────────────────────────────────

/// A horizontal row of hairline-separated cells that all share available width.
class SplitRow extends StatelessWidget {
  final List<Widget> children;

  const SplitRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cells = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        cells.add(Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          color: palette.hairline,
        ));
      }
      cells.add(Expanded(child: children[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells);
  }
}

/// A settings-style row.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final tint = destructive
        ? palette.danger
        : (iconColor ?? palette.inkSoft);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: AppSpacing.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
          child: Row(
            children: [
              Icon(icon, size: 21, color: tint),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: destructive ? palette.danger : palette.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: palette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped list of [SettingsRow]s inside one bordered surface.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxl + AppSpacing.md),
          child: Divider(height: 1, color: palette.hairline),
        ));
      }
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xs, bottom: AppSpacing.sm),
            child: Text(
              title!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
        AppCard(padding: EdgeInsets.zero, child: Column(children: rows)),
      ],
    );
  }
}

/// A progress bar with a labelled start and end.
class JourneyProgressBar extends StatelessWidget {
  /// 0 to 1.
  final double progress;
  final String startLabel;
  final String endLabel;
  final String? centreLabel;

  const JourneyProgressBar({
    super.key,
    required this.progress,
    required this.startLabel,
    required this.endLabel,
    this.centreLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final clamped = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                startLabel,
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (centreLabel != null)
              Text(
                centreLabel!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: palette.brand),
              ),
            Expanded(
              child: Text(
                endLabel,
                style: theme.textTheme.labelSmall,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          value: '${(clamped * 100).round()}% complete',
          child: ClipRRect(
            borderRadius: AppSpacing.brPill,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clamped),
              duration: AppMotion.slow,
              curve: AppMotion.enter,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: palette.hairline,
                valueColor: AlwaysStoppedAnimation(palette.brand),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animation helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Staggered entrance for a list of children.
///
/// Centralised so every screen animates identically and no screen invents its
/// own delay ladder.
extension StaggerAnimation on Widget {
  Widget staggerIn(int index, {Duration? delay}) {
    return animate(delay: delay ?? (AppMotion.stagger * index))
        .fadeIn(duration: AppMotion.normal, curve: AppMotion.enter)
        .slideY(begin: 0.08, end: 0, curve: AppMotion.enter);
  }

  Widget fadeInUp({Duration? delay}) {
    return animate(delay: delay ?? Duration.zero)
        .fadeIn(duration: AppMotion.normal, curve: AppMotion.enter)
        .slideY(begin: 0.06, end: 0, curve: AppMotion.enter);
  }
}
