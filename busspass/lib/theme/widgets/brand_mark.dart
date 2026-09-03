import 'package:flutter/material.dart';
import '../app_colors.dart';

/// The BussPass logomark — a circular seal. Deliberately understated:
/// a hairline ring around a solid bus glyph on the brand colour, so it works
/// at small sizes both light and dark.
class BrandMark extends StatelessWidget {
  final double size;
  final bool inverse;

  const BrandMark({super.key, this.size = 64, this.inverse = false});

  @override
  Widget build(BuildContext context) {
    final bg = inverse ? AppColors.surface : AppColors.brand;
    final fg = inverse ? AppColors.brand : AppColors.surface;
    final ring = inverse ? AppColors.hairline : Colors.white.withValues(alpha: 0.25);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1),
      ),
      child: Icon(
        Icons.directions_bus_filled_rounded,
        size: size * 0.44,
        color: fg,
      ),
    );
  }
}