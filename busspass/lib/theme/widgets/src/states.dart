/// Loading / empty / error states: [EmptyState], [ErrorState], the shimmer
/// system ([Shimmer], [SkeletonBox], [SkeletonCard], [SkeletonListTile],
/// [SkeletonList]).
library;

import 'package:flutter/material.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

import 'buttons.dart' show PrimaryButton;
import 'surfaces.dart' show AppCard;

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

/// Marks a subtree as being driven by an ancestor [Shimmer], so descendant
/// [SkeletonBox]es paint a plain opaque block and let the shared sweep animate
/// them — one controller for the whole group rather than one per box.
class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required super.child});

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) => false;
}

/// Sweeps a highlight gradient across its subtree — the canonical shimmer
/// loading effect.
///
/// Wrap a group of [SkeletonBox]es in a single [Shimmer] so the whole skeleton
/// animates as one coherent sweep. A lone [SkeletonBox] with no [Shimmer]
/// ancestor wraps itself, so shimmer works everywhere without ceremony.
///
/// Palette-aware: the base is a hairline neutral and the highlight lifts toward
/// the surface colour, so it reads correctly in both light and dark themes.
class Shimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const Shimmer({super.key, required this.child, this.enabled = true});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final palette = context.palette;
    final base = palette.hairline;
    final highlight = context.isDark
        ? palette.hairlineStrong
        : palette.surface;

    return _ShimmerScope(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: const [0.15, 0.5, 0.85],
              transform: _Sweep(_controller.value),
            ).createShader(bounds),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Slides the shimmer gradient from off-screen left to off-screen right.
class _Sweep extends GradientTransform {
  final double t;
  const _Sweep(this.t);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // -1 → gradient fully left of the box, 1 → fully right of it.
    final dx = (t * 2 - 1) * bounds.width;
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// A placeholder block for a loading state with a known shape.
///
/// Opaque by design: when wrapped in a [Shimmer] it becomes the canvas the
/// sweep paints over. On its own it self-wraps so it still shimmers.
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
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.hairline,
        borderRadius: borderRadius,
      ),
    );

    // Already inside a shimmer group — paint plain and let the group animate.
    if (context.dependOnInheritedWidgetOfExactType<_ShimmerScope>() != null) {
      return box;
    }
    return Shimmer(child: box);
  }
}

/// A skeleton shaped like a result card, so loading does not shift the layout.
class SkeletonCard extends StatelessWidget {
  final double? width;

  const SkeletonCard({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              SkeletonBox(width: 44, height: 44, borderRadius: AppSpacing.brSm),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 130, height: 15),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ),
              SkeletonBox(width: 52, height: 22, borderRadius: AppSpacing.brPill),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const SkeletonBox(height: 11),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: width == null ? 210 : null,
              child: const SkeletonBox(height: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// A skeleton shaped like a compact list row (leading square + two lines).
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          SkeletonBox(width: 42, height: 42, borderRadius: AppSpacing.brSm),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 160, height: 13),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 100, height: 11),
              ],
            ),
          ),
          SkeletonBox(width: 40, height: 13),
        ],
      ),
    );
  }
}

/// A vertical list of skeletons wrapped in one shimmer group, for full-screen
/// loading states. [variant] chooses between card and list-row shapes.
class SkeletonList extends StatelessWidget {
  final int count;
  final SkeletonVariant variant;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 4,
    this.variant = SkeletonVariant.card,
    this.padding = const EdgeInsets.all(AppSpacing.pageInset),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <Widget>[];
    for (var i = 0; i < count; i++) {
      switch (variant) {
        case SkeletonVariant.card:
          items.add(const SkeletonCard());
          items.add(const SizedBox(height: AppSpacing.md));
        case SkeletonVariant.listTile:
          items.add(const SkeletonListTile());
          if (i < count - 1) {
            items.add(Divider(height: 1, color: palette.hairline));
          }
      }
    }

    return Shimmer(
      child: Padding(
        padding: padding,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items,
          ),
        ),
      ),
    );
  }
}

enum SkeletonVariant { card, listTile }
