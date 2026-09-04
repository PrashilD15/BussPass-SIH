/// Geodesic and polyline geometry.
///
/// Everything the app needs to answer "where am I on this route, and how far is
/// left" lives here. Distances are kilometres, bearings are degrees clockwise
/// from true north, and all trigonometry is done in radians internally.
///
/// The Earth is modelled as a sphere of mean radius 6371.0088 km (IUGG). Over
/// MSRTC corridor lengths (60–840 km) the spherical error against WGS-84 is
/// under 0.5%, well inside the uncertainty of the published road distances the
/// app is matching against.
library;

import 'dart:math' as math;

/// A latitude/longitude pair, decoupled from any mapping SDK so the geometry
/// is unit-testable without a Flutter binding.
class GeoPoint {
  final double lat;
  final double lng;

  const GeoPoint(this.lat, this.lng);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() =>
      'GeoPoint(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
}

/// Result of snapping an arbitrary point onto a polyline.
class PolylineProjection {
  /// The closest point on the polyline.
  final GeoPoint point;

  /// Perpendicular distance from the query point to [point], in kilometres.
  final double offsetKm;

  /// Distance from the start of the polyline to [point], along the polyline.
  final double alongKm;

  /// Index of the polyline segment containing [point]. Segment `i` spans
  /// vertices `i` and `i + 1`.
  final int segmentIndex;

  /// Position within the segment, 0 at the start vertex and 1 at the end.
  final double segmentT;

  const PolylineProjection({
    required this.point,
    required this.offsetKm,
    required this.alongKm,
    required this.segmentIndex,
    required this.segmentT,
  });
}

class Geo {
  Geo._();

  /// IUGG mean Earth radius, kilometres.
  static const double earthRadiusKm = 6371.0088;

  static const double _deg2rad = math.pi / 180.0;
  static const double _rad2deg = 180.0 / math.pi;

  /// Great-circle distance between two points, in kilometres.
  ///
  /// Uses the haversine form, which stays numerically stable for the short
  /// distances (metres) that GPS matching produces, where the spherical law of
  /// cosines loses precision.
  static double distanceKm(GeoPoint a, GeoPoint b) {
    final lat1 = a.lat * _deg2rad;
    final lat2 = b.lat * _deg2rad;
    final dLat = lat2 - lat1;
    final dLng = (b.lng - a.lng) * _deg2rad;

    final sinHalfLat = math.sin(dLat / 2);
    final sinHalfLng = math.sin(dLng / 2);
    final h = sinHalfLat * sinHalfLat +
        math.cos(lat1) * math.cos(lat2) * sinHalfLng * sinHalfLng;

    // Clamp guards against a hair over 1.0 from floating-point accumulation,
    // which would make asin return NaN for antipodal-ish inputs.
    return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// Great-circle distance in metres.
  static double distanceMeters(GeoPoint a, GeoPoint b) =>
      distanceKm(a, b) * 1000.0;

  /// Initial bearing from [a] to [b], in degrees clockwise from north (0–360).
  static double bearing(GeoPoint a, GeoPoint b) {
    final lat1 = a.lat * _deg2rad;
    final lat2 = b.lat * _deg2rad;
    final dLng = (b.lng - a.lng) * _deg2rad;

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final deg = math.atan2(y, x) * _rad2deg;
    return (deg + 360.0) % 360.0;
  }

  /// Smallest absolute difference between two bearings, in degrees (0–180).
  ///
  /// Used by transit detection to compare a user's heading against a bus's
  /// heading without a 359°-vs-1° false negative.
  static double bearingDelta(double a, double b) {
    final diff = ((a - b) % 360.0 + 360.0) % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  /// Point at [fraction] of the way from [a] to [b] along the great circle.
  ///
  /// Falls back to linear interpolation when the two points are nearly
  /// coincident, where the spherical formula divides by a vanishing sine.
  static GeoPoint interpolate(GeoPoint a, GeoPoint b, double fraction) {
    if (fraction <= 0) return a;
    if (fraction >= 1) return b;

    final lat1 = a.lat * _deg2rad;
    final lng1 = a.lng * _deg2rad;
    final lat2 = b.lat * _deg2rad;
    final lng2 = b.lng * _deg2rad;

    final d = distanceKm(a, b) / earthRadiusKm;
    final sinD = math.sin(d);
    if (sinD.abs() < 1e-12) {
      return GeoPoint(
        a.lat + (b.lat - a.lat) * fraction,
        a.lng + (b.lng - a.lng) * fraction,
      );
    }

    final A = math.sin((1 - fraction) * d) / sinD;
    final B = math.sin(fraction * d) / sinD;

    final x = A * math.cos(lat1) * math.cos(lng1) +
        B * math.cos(lat2) * math.cos(lng2);
    final y = A * math.cos(lat1) * math.sin(lng1) +
        B * math.cos(lat2) * math.sin(lng2);
    final z = A * math.sin(lat1) + B * math.sin(lat2);

    final lat = math.atan2(z, math.sqrt(x * x + y * y));
    final lng = math.atan2(y, x);
    return GeoPoint(lat * _rad2deg, lng * _rad2deg);
  }

  /// Total length of a polyline, in kilometres.
  static double polylineLengthKm(List<GeoPoint> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += distanceKm(points[i], points[i + 1]);
    }
    return total;
  }

  /// Cumulative distance to each vertex of a polyline. Always starts at 0 and
  /// has the same length as [points].
  static List<double> cumulativeKm(List<GeoPoint> points) {
    final out = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      out[i] = out[i - 1] + distanceKm(points[i - 1], points[i]);
    }
    return out;
  }

  /// Snap [query] onto the closest point of [points].
  ///
  /// Each segment is projected in a local east-north tangent plane centred on
  /// the segment start. Over segment lengths of a few kilometres this is
  /// accurate to well under a metre, and it avoids the cost and instability of
  /// a full spherical cross-track solution at every GPS tick.
  ///
  /// Returns `null` only when [points] is empty.
  static PolylineProjection? projectOnPolyline(
    GeoPoint query,
    List<GeoPoint> points,
  ) {
    if (points.isEmpty) return null;
    if (points.length == 1) {
      return PolylineProjection(
        point: points.first,
        offsetKm: distanceKm(query, points.first),
        alongKm: 0,
        segmentIndex: 0,
        segmentT: 0,
      );
    }

    // Metres per degree at this latitude. Longitude degrees shrink by cos(lat).
    const metersPerDegLat = 111132.92;
    final cosLat = math.cos(query.lat * _deg2rad);

    double? bestOffsetKm;
    var bestIndex = 0;
    var bestT = 0.0;
    var bestPoint = points.first;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      final metersPerDegLng = metersPerDegLat * cosLat;
      final ax = 0.0;
      final ay = 0.0;
      final bx = (b.lng - a.lng) * metersPerDegLng;
      final by = (b.lat - a.lat) * metersPerDegLat;
      final px = (query.lng - a.lng) * metersPerDegLng;
      final py = (query.lat - a.lat) * metersPerDegLat;

      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;

      double t;
      if (lenSq < 1e-9) {
        t = 0.0; // degenerate segment (duplicate vertex)
      } else {
        t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
        t = t.clamp(0.0, 1.0);
      }

      final projected = interpolate(a, b, t);
      final offset = distanceKm(query, projected);

      if (bestOffsetKm == null || offset < bestOffsetKm) {
        bestOffsetKm = offset;
        bestIndex = i;
        bestT = t;
        bestPoint = projected;
      }
    }

    final cum = cumulativeKm(points);
    final segLen = distanceKm(points[bestIndex], points[bestIndex + 1]);
    final alongKm = cum[bestIndex] + segLen * bestT;

    return PolylineProjection(
      point: bestPoint,
      offsetKm: bestOffsetKm ?? 0,
      alongKm: alongKm,
      segmentIndex: bestIndex,
      segmentT: bestT,
    );
  }

  /// The point [targetKm] along [points] from its start.
  ///
  /// Clamps to the endpoints when [targetKm] falls outside the polyline. This
  /// is how the bus simulator turns "distance travelled" into a map position.
  static GeoPoint pointAtDistance(List<GeoPoint> points, double targetKm) {
    if (points.isEmpty) return const GeoPoint(0, 0);
    if (points.length == 1 || targetKm <= 0) return points.first;

    var remaining = targetKm;
    for (var i = 0; i < points.length - 1; i++) {
      final segLen = distanceKm(points[i], points[i + 1]);
      if (remaining <= segLen) {
        final t = segLen < 1e-9 ? 0.0 : remaining / segLen;
        return interpolate(points[i], points[i + 1], t);
      }
      remaining -= segLen;
    }
    return points.last;
  }

  /// Heading of the polyline at [targetKm] along it, in degrees from north.
  static double bearingAtDistance(List<GeoPoint> points, double targetKm) {
    if (points.length < 2) return 0;
    var remaining = math.max(0.0, targetKm);
    for (var i = 0; i < points.length - 1; i++) {
      final segLen = distanceKm(points[i], points[i + 1]);
      if (remaining <= segLen || i == points.length - 2) {
        return bearing(points[i], points[i + 1]);
      }
      remaining -= segLen;
    }
    return bearing(points[points.length - 2], points.last);
  }

  /// Slice the sub-polyline between two distances along [points].
  ///
  /// The returned list includes exact interpolated endpoints, so drawing it
  /// produces a line that starts and ends precisely where asked rather than at
  /// the nearest vertex.
  static List<GeoPoint> slice(
    List<GeoPoint> points,
    double fromKm,
    double toKm,
  ) {
    if (points.length < 2) return List.of(points);
    final start = math.min(fromKm, toKm);
    final end = math.max(fromKm, toKm);

    final cum = cumulativeKm(points);
    final total = cum.last;
    final a = start.clamp(0.0, total);
    final b = end.clamp(0.0, total);
    if (b - a < 1e-9) return [pointAtDistance(points, a)];

    final out = <GeoPoint>[pointAtDistance(points, a)];
    for (var i = 0; i < points.length; i++) {
      if (cum[i] > a && cum[i] < b) out.add(points[i]);
    }
    out.add(pointAtDistance(points, b));
    return out;
  }

  /// Axis-aligned bounding box of [points] as `(southWest, northEast)`.
  ///
  /// Returns `null` for an empty list. Does not handle antimeridian crossing —
  /// irrelevant for an Indian transit network.
  static (GeoPoint, GeoPoint)? bounds(List<GeoPoint> points) {
    if (points.isEmpty) return null;
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    return (GeoPoint(minLat, minLng), GeoPoint(maxLat, maxLng));
  }

  /// Bounding box padded by [padKm] on every side.
  ///
  /// Used to fit a route on the map with breathing room instead of clipping the
  /// terminal markers at the viewport edge.
  static (GeoPoint, GeoPoint)? paddedBounds(
    List<GeoPoint> points, {
    double padKm = 8,
  }) {
    final box = bounds(points);
    if (box == null) return null;
    final (sw, ne) = box;

    final latPad = padKm / 110.574;
    final midLat = (sw.lat + ne.lat) / 2;
    final cosLat = math.cos(midLat * _deg2rad).abs();
    final lngPad = padKm / (111.320 * (cosLat < 0.01 ? 0.01 : cosLat));

    return (
      GeoPoint(sw.lat - latPad, sw.lng - lngPad),
      GeoPoint(ne.lat + latPad, ne.lng + lngPad),
    );
  }

  /// Format a distance for display: metres under 1 km, one decimal under
  /// 10 km, whole kilometres above.
  static String formatKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }
}
