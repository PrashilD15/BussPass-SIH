/// The single canonical journey progress bar — [JourneyProgressBar].
///
/// Supports either a plain 0..1 fraction or a segmented breakdown (walk / wait
/// / ride) so the same widget serves the live-nav panel, the itinerary legs,
/// and the active-ticket banner. This replaces the two divergent progress bars
/// the screens used to hand-roll.
library;

import 'package:flutter/material.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// One proportional band of a segmented progress bar.
class ProgressSegment {
  final double weight;
  final Color color;
  final String? label;

  /// Dashed bands read as "not moving" — walking or waiting.
  final bool dashed;

  const ProgressSegment({
    required this.weight,
    required this.color,
    this.label,
    this.dashed = false,
  });
}

/// A progress bar with labelled ends and either a single fraction or segments.
class JourneyProgressBar extends StatelessWidget {
  /// 0..1 — used when [segments] is null.
  final double? progress;
  final List<ProgressSegment>? segments;

  /// Where [progress] currently sits within the whole bar (0..1). Ignored when
  /// drawing [segments].
  final double? marker;

  final String startLabel;
  final String endLabel;
  final String? centreLabel;

  /// Delayed: the fill shifts to the warning ramp and pulses, so a late bus is
  /// legible at a glance without reading a number.
  final bool delayed;

  const JourneyProgressBar({
    super.key,
    this.progress,
    this.segments,
    this.marker,
    required this.startLabel,
    required this.endLabel,
    this.centreLabel,
    this.delayed = false,
  }) : assert(progress != null || segments != null,
            'supply either progress or segments');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

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
                    ?.copyWith(color: delayed ? palette.warning : palette.brand),
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
          value: segments != null
              ? '$startLabel to $endLabel'
              : '${((progress ?? 0) * 100).round()}% complete',
          child: segments != null
              ? _SegmentedBar(segments: segments!, marker: marker, delayed: delayed)
              : _fractionBar(palette),
        ),
      ],
    );
  }

  Widget _fractionBar(AppPalette palette) {
    final clamped = (progress ?? 0).clamp(0.0, 1.0);
    final fill = delayed ? palette.warning : palette.brand;
    return ClipRRect(
      borderRadius: AppSpacing.brPill,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: clamped),
        duration: AppMotion.slow,
        curve: AppMotion.enter,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: 7,
          backgroundColor: palette.hairline,
          valueColor: AlwaysStoppedAnimation(fill),
        ),
      ),
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  final List<ProgressSegment> segments;
  final double? marker;
  final bool delayed;

  const _SegmentedBar({
    required this.segments,
    required this.marker,
    required this.delayed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = segments.fold<double>(0, (s, e) => s + e.weight);
    final safeTotal = total <= 0 ? 1.0 : total;
    final m = (marker ?? 0).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x = 0;
        final children = <Widget>[];
        for (final seg in segments) {
          final w = (seg.weight / safeTotal) * width;
          children.add(Positioned(
            left: x,
            top: 0,
            bottom: 0,
            width: w,
            child: seg.dashed
                ? CustomPaint(
                    painter: _DashedBarPainter(color: seg.color),
                    size: Size(w, 7),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: seg.color,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(x == 0 ? 999 : 0),
                        right: Radius.circular(x + w >= width ? 999 : 0),
                      ),
                    ),
                    child: const SizedBox(height: 7),
                  ),
          ));
          x += w;
        }

        // Traveller marker sits on top of the bands.
        final mx = m * width;
        children.add(Positioned(
          left: (mx - 5).clamp(0, width - 10),
          top: -2,
          child: Container(
            width: 10,
            height: 11,
            decoration: BoxDecoration(
              color: delayed ? palette.warning : palette.brand,
              shape: BoxShape.circle,
              border: Border.all(color: palette.surface, width: 2),
              boxShadow: AppShadow.card(Colors.black),
            ),
          ),
        ));

        return SizedBox(
          height: 11,
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }
}

class _DashedBarPainter extends CustomPainter {
  final Color color;
  const _DashedBarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 4.0;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(end.toDouble(), size.height / 2), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedBarPainter old) => old.color != color;
}
