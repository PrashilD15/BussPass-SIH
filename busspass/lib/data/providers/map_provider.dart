import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:busspass/data/models/bus_models.dart';
import 'package:busspass/data/repositories/bus_stop_repository.dart';

// ── Repository provider ──────────────────────────────────────────────────────
final busStopRepositoryProvider = Provider<BusStopRepository>((ref) {
  return BusStopRepository();
});

// ── All bus stops ────────────────────────────────────────────────────────────
final allBusStopsProvider = FutureProvider<List<BusStop>>((ref) async {
  return ref.read(busStopRepositoryProvider).getAllStops();
});

// ── User's current location ──────────────────────────────────────────────────
final userLocationProvider = FutureProvider<Position?>((ref) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) return null;

  return await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
    ),
  );
});

// ── Custom Marker Generator ──────────────────────────────────────────────────
Future<BitmapDescriptor> _createCustomBusStopMarker() async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);

  // Draw background circle (Premium Slate)
  final Paint backgroundPaint = Paint()..color = const Color(0xFF2F3E46);
  canvas.drawCircle(const Offset(60, 50), 40, backgroundPaint);

  // Draw border (White)
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8;
  canvas.drawCircle(const Offset(60, 50), 40, borderPaint);

  // Draw pointer (triangle at bottom)
  final Path pointerPath = Path()
    ..moveTo(40, 85)
    ..lineTo(80, 85)
    ..lineTo(60, 110)
    ..close();
  canvas.drawPath(pointerPath, backgroundPaint);

  // Draw bus icon
  TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
  textPainter.text = TextSpan(
    text: String.fromCharCode(Icons.directions_bus_rounded.codePoint),
    style: TextStyle(
      fontSize: 48.0,
      fontFamily: Icons.directions_bus_rounded.fontFamily,
      package: Icons.directions_bus_rounded.fontPackage,
      color: Colors.white,
    ),
  );
  textPainter.layout();
  textPainter.paint(
      canvas, Offset(60 - (textPainter.width / 2), 50 - (textPainter.height / 2)));

  final ui.Image image = await pictureRecorder.endRecording().toImage(120, 120);
  final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List uint8List = byteData!.buffer.asUint8List();

  return BitmapDescriptor.bytes(uint8List);
}

// ── Convert bus stops to map markers ─────────────────────────────────────────
final busStopMarkersProvider = FutureProvider<Set<Marker>>((ref) async {
  final stops = await ref.watch(allBusStopsProvider.future);
  final customIcon = await _createCustomBusStopMarker();

  return stops.asMap().entries.map((entry) {
    final stop = entry.value;
    return Marker(
      markerId: MarkerId(stop.id),
      position: LatLng(stop.lat, stop.lng),
      infoWindow: InfoWindow(
        title: stop.name,
        snippet: stop.city,
      ),
      icon: customIcon,
    );
  }).toSet();
});
