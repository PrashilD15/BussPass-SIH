/// [BusMarker] — the live-fleet map marker: a coloured dot badge whose fill
/// matches the crowd level, drawn once into a BitmapDescriptor. Heading
/// rotation is applied on the `Marker` itself (flat: true), so this bitmap
/// only needs to be legible from above.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BusMarker {
  BusMarker._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Synchronously returns a previously rendered bitmap for this style, or
  /// null. Map frame loops call this on every redraw and [create] on a miss.
  static BitmapDescriptor? cached({
    required Color fill,
    bool simulated = false,
    bool selected = false,
  }) =>
      _cache['${fill.toARGB32()}_${simulated}_$selected'];

  /// Render (and cache) a circular bus badge. `simulated` buses get a hollow
  /// centre so they're distinguishable from real GPS reports at a glance.
  static Future<BitmapDescriptor> create({
    required Color fill,
    bool simulated = false,
    bool selected = false,
    double size = 64,
  }) async {
    final key = '${fill.toARGB32()}_${simulated}_$selected';
    final cached = _cache[key];
    if (cached != null) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size * 0.38;

    // Contact shadow.
    canvas.drawCircle(
      center.translate(0, 2),
      radius + 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // White ring — a fatter one marks selection.
    canvas.drawCircle(
      center,
      radius + (selected ? 4 : 2.5),
      Paint()..color = Colors.white,
    );

    // Fill disc.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = fill,
    );

    // Hollow centre for simulated reports.
    if (simulated) {
      canvas.drawCircle(
        center,
        radius * 0.55,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        center,
        radius * 0.28,
        Paint()..color = fill,
      );
    }

    // Bus glyph for real reports.
    if (!simulated) {
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(Icons.bus_alert_rounded.codePoint),
          style: TextStyle(
            fontSize: radius * 1.25,
            fontFamily: Icons.bus_alert_rounded.fontFamily,
            color: Colors.white,
          ),
        )
        ..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final descriptor =
        BitmapDescriptor.bytes(data!.buffer.asUint8List());
    _cache[key] = descriptor;
    return descriptor;
  }

  static void clearCache() => _cache.clear();
}
