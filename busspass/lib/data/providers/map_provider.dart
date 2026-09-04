import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart';

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

// ── Current Map Zoom ────────────────────────────────────────────────────────
class CurrentMapZoomNotifier extends Notifier<double> {
  @override
  double build() => 12.0;
  void setZoom(double z) => state = z;
}

final currentMapZoomProvider =
    NotifierProvider<CurrentMapZoomNotifier, double>(CurrentMapZoomNotifier.new);

final busStopMarkerScaleProvider = Provider<double>((ref) {
  final zoom = ref.watch(currentMapZoomProvider);
  if (zoom < 6.5) return 0.25;
  if (zoom < 8.5) return 0.4;
  if (zoom < 10.5) return 0.6;
  if (zoom < 12.0) return 0.8;
  return 1.0;
});

// ── Custom Marker Generator ──────────────────────────────────────────────────
Future<BitmapDescriptor> _createCustomBusStopMarker(double scale) async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);

  canvas.scale(scale, scale);

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
  textPainter.paint(canvas,
      Offset(60 - (textPainter.width / 2), 50 - (textPainter.height / 2)));

  final int size = (120 * scale).round();
  final ui.Image image = await pictureRecorder.endRecording().toImage(size, size);
  final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List uint8List = byteData!.buffer.asUint8List();

  return BitmapDescriptor.bytes(uint8List);
}

// ── Convert bus stops to map markers ─────────────────────────────────────────

/// A tappable stop marker plus its backing stop.
///
/// The tab attaches the `Marker.onTap` so tapping a marker opens the stop's
/// detail sheet. Separating the stop from the marker here is what lets the
/// marker stay a plain Google Maps object while the sheet keeps a real
/// [NetworkStop].
typedef StopTapTarget = ({Marker marker, NetworkStop stop});

/// One marker per stop, carrying its backing stop so a tap can be resolved.
final busStopTargetsProvider = FutureProvider<List<StopTapTarget>>((ref) async {
  final stops = await ref.watch(allStopsProvider.future);
  final scale = ref.watch(busStopMarkerScaleProvider);
  final customIcon = await _createCustomBusStopMarker(scale);

  return stops
      .map((stop) => (
            marker: Marker(
              markerId: MarkerId(stop.id),
              position: LatLng(stop.lat, stop.lng),
              infoWindow: InfoWindow(
                title: stop.name,
                snippet: stop.city,
              ),
              icon: customIcon,
            ),
            stop: stop,
          ))
      .toList();
});

/// Backward-compatible set of markers for map renders that do not need taps.
final busStopMarkersProvider = FutureProvider<Set<Marker>>((ref) async {
  final targets = await ref.watch(busStopTargetsProvider.future);
  return targets.map((t) => t.marker).toSet();
});
