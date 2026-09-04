import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:busspass/core/constants/api_keys.dart';

/// A decoded point on a directions route.
class RoadPoint {
  final double latitude;
  final double longitude;
  const RoadPoint(this.latitude, this.longitude);

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Result of a directions lookup: the road-snapped polyline points plus
/// route metadata.
class DirectionsResult {
  final List<RoadPoint> points;
  final int distanceMeters;
  final int durationSeconds;
  final String? summary;
  const DirectionsResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.summary,
  });
}

/// Road-snapped routing polyline provider.
///
/// Primary source is the **OSRM public routing API** — it returns encoded
/// polylines that follow real roads (navigation-app look) and needs **no API
/// key**, so it works out-of-the-box on the device. If the Google Maps
/// Directions API is later enabled for the project key, it is used first and
/// OSRM acts as the fallback.
class DirectionsService {
  DirectionsService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const String _osrmBase = 'https://router.project-osrm.org/route/v1/driving';
  static const String _googleBase =
      'https://maps.googleapis.com/maps/api/directions/json';

  /// Request a road-snapped route through [origin], [waypoints] and
  /// [destination]. Returns `null` on any failure (network, quota, no route)
  /// so callers can fall back to their stop-connected polyline.
  Future<DirectionsResult?> route({
    required LatLng origin,
    required List<LatLng> waypoints,
    required LatLng destination,
  }) async {
    final osrm = await _osrm(origin, waypoints, destination);
    if (osrm != null) return osrm;
    return _google(origin, waypoints, destination);
  }

  /// OSRM — no key needed, robust and fast. Coordinates are lon,lat pairs.
  Future<DirectionsResult?> _osrm(
      LatLng origin, List<LatLng> waypoints, LatLng destination) async {
    final coords = [origin, ...waypoints, destination]
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final uri = Uri.parse(
        '$_osrmBase/$coords?overview=full&geometries=polyline&steps=false');
    try {
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final routes = (body['routes'] as List?) ?? [];
      if (routes.isEmpty) return null;
      final r = routes.first as Map<String, dynamic>;
      final geometry = r['geometry'] as String?;
      if (geometry == null || geometry.isEmpty) return null;
      return DirectionsResult(
        points: decodePolyline(geometry),
        distanceMeters: (r['distance'] as num?)?.round() ?? 0,
        durationSeconds: (r['duration'] as num?)?.round() ?? 0,
        summary: 'via roads',
      );
    } catch (_) {
      return null;
    }
  }

  /// Google Directions API — only used if it has been enabled for the key.
  Future<DirectionsResult?> _google(
      LatLng origin, List<LatLng> waypoints, LatLng destination) async {
    final query = {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'waypoints': waypoints.isEmpty
          ? null
          : waypoints
              .map((p) => '${p.latitude},${p.longitude}')
              .join('|'),
      'mode': ApiKeys.directionsMode,
      'key': ApiKeys.googleMapsApiKey,
    }..removeWhere((_, v) => v == null);

    try {
      final res = await _client
          .get(
              Uri.parse(_googleBase).replace(queryParameters: query),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final route = (body['routes'] as List?)?.isNotEmpty == true
          ? (body['routes'] as List).first as Map<String, dynamic>
          : null;
      if (route == null) return null;
      final legs = (route['legs'] as List?) ?? [];
      int distanceMeters = 0;
      int durationSeconds = 0;
      for (final leg in legs) {
        final m = leg as Map<String, dynamic>;
        distanceMeters += (m['distance']?['value'] as num?)?.toInt() ?? 0;
        durationSeconds += (m['duration']?['value'] as num?)?.toInt() ?? 0;
      }
      final overview =
          (route['overview_polyline'] as Map?)?['points'] as String?;
      if (overview == null || overview.isEmpty) return null;
      return DirectionsResult(
        points: decodePolyline(overview),
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        summary: route['summary'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decode a Google/OSRM encoded polyline string into [RoadPoint]s.
  static List<RoadPoint> decodePolyline(String encoded) {
    final poly = <RoadPoint>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int result = 0;
      int shift = 0;
      int b;
      do {
        if (index >= len) break;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        if (index >= len) break;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(RoadPoint(lat / 1e5, lng / 1e5));
    }
    return poly;
  }
}
