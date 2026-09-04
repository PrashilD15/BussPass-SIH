import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:busspass/theme/app_colors.dart';

/// The BussPass mark: a route line threading through two stop nodes, enclosed in
/// a circular seal.
///
/// Drawn rather than shipped as an asset so it scales crisply at any size and
/// recolours with the palette — the mark on a dark background is not the light
/// mark with a filter over it.
class BrandMark extends StatelessWidget {
  final double size;

  /// Draw light-on-dark instead of dark-on-light.
  final bool inverse;

  /// Override the mark colour.
  final Color? color;

  const BrandMark({
    super.key,
    this.size = 64,
    this.inverse = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground =
        color ?? (inverse ? palette.onBrand : palette.brand);
    final background = inverse ? palette.brand : palette.brandLight;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandMarkPainter(
          foreground: foreground,
          background: background,
          ring: inverse
              ? palette.onBrand.withValues(alpha: 0.28)
              : palette.brand.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final Color foreground;
  final Color background;
  final Color ring;

  const _BrandMarkPainter({
    required this.foreground,
    required this.background,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(centre, radius, Paint()..color = background);
    canvas.drawCircle(
      centre,
      radius - 0.75,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // The route: an S-curve from lower-left to upper-right, the shape of a road
    // threading between two towns.
    final unit = size.width / 64;
    final path = Path()
      ..moveTo(centre.dx - 15 * unit, centre.dy + 13 * unit)
      ..cubicTo(
        centre.dx - 4 * unit, centre.dy + 11 * unit,
        centre.dx - 11 * unit, centre.dy - 8 * unit,
        centre.dx + 1 * unit, centre.dy - 10 * unit,
      )
      ..cubicTo(
        centre.dx + 11 * unit, centre.dy - 11.5 * unit,
        centre.dx + 13 * unit, centre.dy - 4 * unit,
        centre.dx + 15 * unit, centre.dy - 1 * unit,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * unit
        ..strokeCap = StrokeCap.round,
    );

    // Origin node: hollow, the way a map marks a departure point.
    final originCentre = Offset(centre.dx - 15 * unit, centre.dy + 13 * unit);
    canvas.drawCircle(originCentre, 4.6 * unit, Paint()..color = background);
    canvas.drawCircle(
      originCentre,
      4.6 * unit,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * unit,
    );

    // Destination node: filled, the terminus.
    canvas.drawCircle(
      Offset(centre.dx + 15 * unit, centre.dy - 1 * unit),
      4.6 * unit,
      Paint()..color = foreground,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) =>
      old.foreground != foreground ||
      old.background != background ||
      old.ring != ring;
}

/// The wordmark, for headers and the splash.
class BrandWordmark extends StatelessWidget {
  final double markSize;
  final bool inverse;

  const BrandWordmark({super.key, this.markSize = 34, this.inverse = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize, inverse: inverse),
        const SizedBox(width: 10),
        Text(
          'BussPass',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: markSize * 0.62,
            letterSpacing: -0.6,
            color: inverse ? palette.onBrand : palette.ink,
          ),
        ),
      ],
    );
  }
}

/// A rotating-halo loading indicator that reads as brand, not as a stock spinner.
class BrandLoader extends StatefulWidget {
  final double size;
  final String? label;

  const BrandLoader({super.key, this.size = 48, this.label});

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _HaloPainter(
                progress: _controller.value,
                color: palette.brand,
                track: palette.hairline,
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _HaloPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _HaloPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawArc(
      rect,
      progress * 2 * math.pi,
      math.pi * 0.7,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.progress != progress;
}
