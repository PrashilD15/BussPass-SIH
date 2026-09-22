import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapMarkerUtils {
  static Future<BitmapDescriptor> createCustomMarker({
    required Color color,
    required double size,
    bool isDestination = false,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Draw a shadow slightly offset
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.location_on.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: Icons.location_on.fontFamily,
        color: Colors.black.withValues(alpha: 0.4),
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 4));

    // Draw the actual pin
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.location_on.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: Icons.location_on.fontFamily,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);

    // If destination, we can add a small star or icon inside?
    // Actually the default location_on has a solid hole? No, it's solid.
    // location_on is solid, location_on_outlined is hollow.
    // Let's just draw a white circle inside the top part of the pin
    final Paint innerDot = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size / 2, size * 0.35), size * 0.15, innerDot);

    if (isDestination) {
      // Same hue as the caller-supplied pin colour — never a hardcoded green.
      final Paint destDot = Paint()..color = color;
      canvas.drawCircle(Offset(size / 2, size * 0.35), size * 0.08, destDot);
    }

    final ui.Image image = await pictureRecorder.endRecording().toImage(
          size.toInt(),
          size.toInt(),
        );
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(uint8List);
  }

  static Future<BitmapDescriptor> createImageMarker({
    required String imageUrl,
    required Color color,
    required double size,
  }) async {
    try {
      final response = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return createCustomMarker(color: color, size: size);

      final ui.Codec codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: size.toInt(),
        targetHeight: size.toInt(),
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image networkImage = frameInfo.image;

      final double pinSize = size * 1.2; // Add some padding for the pin border
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);

      // Draw shadow
      final Paint shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(Offset(pinSize / 2, pinSize / 2), size / 2, shadowPaint);

      // Draw border
      final Paint borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(pinSize / 2, pinSize / 2), (size / 2) + 4, borderPaint);

      // Draw image clipped to circle
      final Path clipPath = Path()..addOval(Rect.fromCircle(center: Offset(pinSize / 2, pinSize / 2), radius: size / 2));
      canvas.clipPath(clipPath);
      
      // Paint the image
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH((pinSize - size) / 2, (pinSize - size) / 2, size, size),
        image: networkImage,
        fit: BoxFit.cover,
      );

      final ui.Image finalImage = await pictureRecorder.endRecording().toImage(
            pinSize.toInt(),
            pinSize.toInt(),
          );
      final ByteData? byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List uint8List = byteData!.buffer.asUint8List();

      return BitmapDescriptor.bytes(uint8List);
    } catch (e) {
      return createCustomMarker(color: color, size: size);
    }
  }
}
