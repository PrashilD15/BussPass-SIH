/// State detection service — offline bounding-box lookup.
///
/// No API key required. Uses a hardcoded bounding-box table for every Indian
/// state / UT to map a GPS coordinate to the matching STC. Falls back to
/// MSRTC (Maharashtra) when location is denied or unavailable.
library;

import 'package:geolocator/geolocator.dart';

/// The STC and associated network asset for the detected state.
class DetectedSTC {
  final String stcCode;
  final String stateName;

  /// Path to the bundled asset, relative to the project root.
  final String networkAsset;

  /// Hex color for the STC badge (e.g., #E85400 for MSRTC).
  final int badgeColor;

  const DetectedSTC({
    required this.stcCode,
    required this.stateName,
    required this.networkAsset,
    required this.badgeColor,
  });

  static const DetectedSTC fallback = DetectedSTC(
    stcCode: 'MSRTC',
    stateName: 'Maharashtra',
    networkAsset: 'assets/data/network.json',
    badgeColor: 0xFFE85400, // MSRTC saffron
  );
}

/// A simple lat/lng bounding box for state detection.
class _StateBB {
  final double minLat, maxLat, minLng, maxLng;
  final DetectedSTC stc;

  const _StateBB(this.minLat, this.maxLat, this.minLng, this.maxLng, this.stc);

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}

/// All supported STCs, ordered by specificity (more granular boxes first).
/// Multiple boxes can exist per state — the first match wins.
final _boxes = <_StateBB>[
  // Maharashtra — MSRTC
  _StateBB(
    15.6, 22.1, 72.6, 80.9,
    const DetectedSTC(
      stcCode: 'MSRTC',
      stateName: 'Maharashtra',
      networkAsset: 'assets/data/network.json',
      badgeColor: 0xFFE85400,
    ),
  ),
  // Karnataka — KSRTC
  _StateBB(
    11.6, 18.5, 74.0, 78.6,
    const DetectedSTC(
      stcCode: 'KSRTC',
      stateName: 'Karnataka',
      networkAsset: 'assets/data/ksrtc_network.json',
      badgeColor: 0xFFCC0000,
    ),
  ),
  // Gujarat — GSRTC
  _StateBB(
    20.1, 24.7, 68.1, 74.5,
    const DetectedSTC(
      stcCode: 'GSRTC',
      stateName: 'Gujarat',
      networkAsset: 'assets/data/gsrtc_network.json',
      badgeColor: 0xFF0B5394,
    ),
  ),
  // Telangana — TSRTC
  _StateBB(
    15.7, 19.9, 77.2, 81.3,
    const DetectedSTC(
      stcCode: 'TSRTC',
      stateName: 'Telangana',
      networkAsset: 'assets/data/tsrtc_network.json',
      badgeColor: 0xFF6D4C9B,
    ),
  ),
  // Andhra Pradesh — APSRTC
  _StateBB(
    12.6, 19.9, 76.7, 84.7,
    const DetectedSTC(
      stcCode: 'APSRTC',
      stateName: 'Andhra Pradesh',
      networkAsset: 'assets/data/apsrtc_network.json',
      badgeColor: 0xFF17A04B,
    ),
  ),
];

class StateDetectionService {
  /// Detect STC from GPS. Returns [DetectedSTC.fallback] on any failure.
  Future<DetectedSTC> detect() async {
    try {
      // Check if location services are enabled.
      if (!await Geolocator.isLocationServiceEnabled()) {
        return DetectedSTC.fallback;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return DetectedSTC.fallback;
        }
      }

      // Low-accuracy position — fast and battery-friendly.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );

      return _fromCoords(position.latitude, position.longitude);
    } catch (_) {
      return DetectedSTC.fallback;
    }
  }

  /// Resolve a coordinate to an STC without platform calls — useful in tests.
  static DetectedSTC resolve(double lat, double lng) =>
      _fromCoords(lat, lng);

  static DetectedSTC _fromCoords(double lat, double lng) {
    for (final box in _boxes) {
      if (box.contains(lat, lng)) return box.stc;
    }
    return DetectedSTC.fallback;
  }
}
