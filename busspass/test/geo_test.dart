import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/geo.dart';

void main() {
  // Real MSRTC stand coordinates, so the assertions are checkable against
  // published road distances.
  const swargate = GeoPoint(18.5013, 73.8567);   // Pune
  const dadar = GeoPoint(19.0178, 72.8478);      // Mumbai
  const lonavala = GeoPoint(18.7481, 73.4072);
  const panvel = GeoPoint(18.9894, 73.1175);
  const nashik = GeoPoint(19.9975, 73.7898);

  group('haversine distance', () {
    test('is zero for identical points', () {
      expect(Geo.distanceKm(swargate, swargate), 0);
    });

    test('is symmetric', () {
      expect(
        Geo.distanceKm(swargate, dadar),
        closeTo(Geo.distanceKm(dadar, swargate), 1e-9),
      );
    });

    test('matches the known Pune–Mumbai great-circle distance', () {
      // Straight-line is ~119 km; the road is 150 km. Both are correct — this
      // asserts the geodesic, not the road.
      expect(Geo.distanceKm(swargate, dadar), closeTo(119, 3));
    });

    test('matches a known short hop', () {
      // Lonavala–Panvel: 24.1 km of latitude and 30.5 km of longitude apart,
      // so ~40.6 km straight-line. The road via NH-48 is about 47 km.
      expect(Geo.distanceKm(lonavala, panvel), closeTo(40.6, 1.0));
    });

    test('satisfies the triangle inequality', () {
      final direct = Geo.distanceKm(swargate, dadar);
      final viaLonavala =
          Geo.distanceKm(swargate, lonavala) + Geo.distanceKm(lonavala, dadar);
      expect(direct, lessThanOrEqualTo(viaLonavala + 1e-6));
    });

    test('one degree of latitude is about 111 km anywhere', () {
      expect(Geo.distanceKm(const GeoPoint(0, 0), const GeoPoint(1, 0)),
          closeTo(111.2, 0.5));
      expect(Geo.distanceKm(const GeoPoint(60, 30), const GeoPoint(61, 30)),
          closeTo(111.2, 0.5));
    });

    test('a degree of longitude shrinks toward the pole', () {
      final atEquator =
          Geo.distanceKm(const GeoPoint(0, 0), const GeoPoint(0, 1));
      final atSixty =
          Geo.distanceKm(const GeoPoint(60, 0), const GeoPoint(60, 1));
      expect(atSixty, closeTo(atEquator * 0.5, 1.0));
    });

    test('handles antipodal points without returning NaN', () {
      final d = Geo.distanceKm(const GeoPoint(0, 0), const GeoPoint(0, 180));
      expect(d.isNaN, isFalse);
      expect(d, closeTo(20015, 5));
    });

    test('metres conversion is consistent', () {
      expect(Geo.distanceMeters(swargate, lonavala),
          closeTo(Geo.distanceKm(swargate, lonavala) * 1000, 1e-6));
    });
  });

  group('bearing', () {
    test('due north is 0', () {
      expect(Geo.bearing(const GeoPoint(0, 0), const GeoPoint(1, 0)),
          closeTo(0, 0.01));
    });

    test('due east is 90', () {
      expect(Geo.bearing(const GeoPoint(0, 0), const GeoPoint(0, 1)),
          closeTo(90, 0.01));
    });

    test('due south is 180', () {
      expect(Geo.bearing(const GeoPoint(1, 0), const GeoPoint(0, 0)),
          closeTo(180, 0.01));
    });

    test('due west is 270', () {
      expect(Geo.bearing(const GeoPoint(0, 1), const GeoPoint(0, 0)),
          closeTo(270, 0.01));
    });

    test('is always in 0–360', () {
      for (final a in [swargate, dadar, nashik, lonavala]) {
        for (final b in [swargate, dadar, nashik, lonavala]) {
          if (a == b) continue;
          final bearing = Geo.bearing(a, b);
          expect(bearing, greaterThanOrEqualTo(0));
          expect(bearing, lessThan(360));
        }
      }
    });

    test('Pune to Mumbai heads north-west', () {
      final b = Geo.bearing(swargate, dadar);
      expect(b, greaterThan(280));
      expect(b, lessThan(340));
    });
  });

  group('bearing delta', () {
    test('is zero for the same heading', () {
      expect(Geo.bearingDelta(90, 90), 0);
    });

    test('does not report 358 degrees for a 2-degree difference', () {
      // The wraparound bug this guards: comparing 359° against 1°.
      expect(Geo.bearingDelta(359, 1), closeTo(2, 1e-9));
      expect(Geo.bearingDelta(1, 359), closeTo(2, 1e-9));
    });

    test('never exceeds 180', () {
      for (var a = 0; a < 360; a += 17) {
        for (var b = 0; b < 360; b += 23) {
          expect(Geo.bearingDelta(a.toDouble(), b.toDouble()),
              lessThanOrEqualTo(180 + 1e-9));
        }
      }
    });

    test('opposite headings differ by 180', () {
      expect(Geo.bearingDelta(0, 180), closeTo(180, 1e-9));
      expect(Geo.bearingDelta(90, 270), closeTo(180, 1e-9));
    });
  });

  group('interpolation', () {
    test('the endpoints are exact', () {
      expect(Geo.interpolate(swargate, dadar, 0), swargate);
      expect(Geo.interpolate(swargate, dadar, 1), dadar);
    });

    test('clamps out-of-range fractions', () {
      expect(Geo.interpolate(swargate, dadar, -0.5), swargate);
      expect(Geo.interpolate(swargate, dadar, 1.5), dadar);
    });

    test('the midpoint is equidistant from both ends', () {
      final mid = Geo.interpolate(swargate, dadar, 0.5);
      final toStart = Geo.distanceKm(mid, swargate);
      final toEnd = Geo.distanceKm(mid, dadar);
      expect(toStart, closeTo(toEnd, 0.01));
      expect(toStart + toEnd, closeTo(Geo.distanceKm(swargate, dadar), 0.01));
    });

    test('a quarter of the way is a quarter of the distance', () {
      final total = Geo.distanceKm(swargate, dadar);
      final quarter = Geo.interpolate(swargate, dadar, 0.25);
      expect(Geo.distanceKm(swargate, quarter), closeTo(total * 0.25, 0.05));
    });

    test('handles near-coincident points without dividing by zero', () {
      const a = GeoPoint(18.5013, 73.8567);
      const b = GeoPoint(18.50130001, 73.85670001);
      final mid = Geo.interpolate(a, b, 0.5);
      expect(mid.lat.isNaN, isFalse);
      expect(mid.lng.isNaN, isFalse);
      expect(mid.lat, closeTo(a.lat, 1e-6));
    });
  });

  group('polyline length', () {
    test('is zero for fewer than two points', () {
      expect(Geo.polylineLengthKm(const []), 0);
      expect(Geo.polylineLengthKm(const [swargate]), 0);
    });

    test('sums the segments', () {
      final line = [swargate, lonavala, panvel, dadar];
      final expected = Geo.distanceKm(swargate, lonavala) +
          Geo.distanceKm(lonavala, panvel) +
          Geo.distanceKm(panvel, dadar);
      expect(Geo.polylineLengthKm(line), closeTo(expected, 1e-9));
    });

    test('a corridor is longer than its straight line', () {
      final corridor = [swargate, lonavala, panvel, dadar];
      expect(Geo.polylineLengthKm(corridor),
          greaterThan(Geo.distanceKm(swargate, dadar)));
    });
  });

  group('cumulative distance', () {
    test('starts at zero and matches the total', () {
      final line = [swargate, lonavala, panvel, dadar];
      final cum = Geo.cumulativeKm(line);
      expect(cum.length, line.length);
      expect(cum.first, 0);
      expect(cum.last, closeTo(Geo.polylineLengthKm(line), 1e-9));
    });

    test('is monotonically increasing', () {
      final cum = Geo.cumulativeKm([swargate, lonavala, panvel, dadar]);
      for (var i = 1; i < cum.length; i++) {
        expect(cum[i], greaterThanOrEqualTo(cum[i - 1]));
      }
    });
  });

  group('projection onto a polyline', () {
    final corridor = [swargate, lonavala, panvel, dadar];

    test('returns null only for an empty polyline', () {
      expect(Geo.projectOnPolyline(swargate, const []), isNull);
      expect(Geo.projectOnPolyline(swargate, [swargate]), isNotNull);
    });

    test('a vertex projects onto itself with zero offset', () {
      final p = Geo.projectOnPolyline(lonavala, corridor)!;
      expect(p.offsetKm, closeTo(0, 0.01));
      expect(p.alongKm,
          closeTo(Geo.distanceKm(swargate, lonavala), 0.05));
    });

    test('the start of the line has zero along-distance', () {
      final p = Geo.projectOnPolyline(swargate, corridor)!;
      expect(p.alongKm, closeTo(0, 0.01));
      expect(p.segmentIndex, 0);
    });

    test('the end of the line has the full along-distance', () {
      final p = Geo.projectOnPolyline(dadar, corridor)!;
      expect(p.alongKm, closeTo(Geo.polylineLengthKm(corridor), 0.05));
    });

    test('a point on a segment lands on that segment with zero offset', () {
      final mid = Geo.interpolate(swargate, lonavala, 0.4);
      final p = Geo.projectOnPolyline(mid, corridor)!;
      expect(p.offsetKm, closeTo(0, 0.02));
      expect(p.segmentIndex, 0);
      expect(p.segmentT, closeTo(0.4, 0.02));
    });

    test('an off-route point reports its perpendicular offset', () {
      // Roughly 10 km north of the Pune–Lonavala segment midpoint.
      final mid = Geo.interpolate(swargate, lonavala, 0.5);
      final offRoute = GeoPoint(mid.lat + 0.09, mid.lng);
      final p = Geo.projectOnPolyline(offRoute, corridor)!;
      expect(p.offsetKm, closeTo(10, 1.5));
    });

    test('a point beyond the end clamps to the terminus', () {
      final beyond = GeoPoint(dadar.lat + 0.5, dadar.lng - 0.5);
      final p = Geo.projectOnPolyline(beyond, corridor)!;
      expect(p.alongKm, closeTo(Geo.polylineLengthKm(corridor), 0.5));
    });

    test('handles a duplicated vertex without dividing by zero', () {
      final degenerate = [swargate, swargate, lonavala];
      final p = Geo.projectOnPolyline(lonavala, degenerate)!;
      expect(p.offsetKm.isNaN, isFalse);
      expect(p.offsetKm, closeTo(0, 0.01));
    });
  });

  group('point at distance', () {
    final corridor = [swargate, lonavala, panvel, dadar];
    final total = Geo.polylineLengthKm(corridor);

    test('zero yields the start', () {
      expect(Geo.pointAtDistance(corridor, 0), swargate);
    });

    test('negative clamps to the start', () {
      expect(Geo.pointAtDistance(corridor, -50), swargate);
    });

    test('beyond the length clamps to the end', () {
      expect(Geo.pointAtDistance(corridor, total + 100), dadar);
    });

    test('is the inverse of projection', () {
      for (final fraction in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        final target = total * fraction;
        final point = Geo.pointAtDistance(corridor, target);
        final back = Geo.projectOnPolyline(point, corridor)!;
        expect(back.alongKm, closeTo(target, 0.1),
            reason: 'round trip failed at fraction $fraction');
      }
    });

    test('an empty polyline yields the origin rather than throwing', () {
      expect(Geo.pointAtDistance(const [], 10), const GeoPoint(0, 0));
    });
  });

  group('bearing at distance', () {
    final corridor = [swargate, lonavala, panvel, dadar];

    test('at the start it matches the first segment', () {
      expect(Geo.bearingAtDistance(corridor, 0),
          closeTo(Geo.bearing(swargate, lonavala), 0.01));
    });

    test('changes as the corridor turns', () {
      final early = Geo.bearingAtDistance(corridor, 5);
      final late = Geo.bearingAtDistance(
          corridor, Geo.polylineLengthKm(corridor) - 5);
      expect(Geo.bearingDelta(early, late), greaterThan(5));
    });

    test('a degenerate polyline yields zero', () {
      expect(Geo.bearingAtDistance(const [swargate], 10), 0);
    });
  });

  group('slice', () {
    final corridor = [swargate, lonavala, panvel, dadar];
    final total = Geo.polylineLengthKm(corridor);

    test('the full range reproduces the length', () {
      final sliced = Geo.slice(corridor, 0, total);
      expect(Geo.polylineLengthKm(sliced), closeTo(total, 0.1));
    });

    test('a sub-range has the requested length', () {
      final sliced = Geo.slice(corridor, 20, 60);
      expect(Geo.polylineLengthKm(sliced), closeTo(40, 0.5));
    });

    test('reversed arguments are normalised', () {
      final forward = Geo.slice(corridor, 20, 60);
      final backward = Geo.slice(corridor, 60, 20);
      expect(Geo.polylineLengthKm(backward),
          closeTo(Geo.polylineLengthKm(forward), 1e-6));
    });

    test('out-of-range bounds clamp', () {
      final sliced = Geo.slice(corridor, -50, total + 50);
      expect(Geo.polylineLengthKm(sliced), closeTo(total, 0.1));
    });

    test('a zero-length range yields a single point', () {
      expect(Geo.slice(corridor, 30, 30).length, 1);
    });
  });

  group('bounds', () {
    test('is null for an empty list', () {
      expect(Geo.bounds(const []), isNull);
    });

    test('contains every input point', () {
      final points = [swargate, dadar, nashik, lonavala];
      final (sw, ne) = Geo.bounds(points)!;
      for (final p in points) {
        expect(p.lat, greaterThanOrEqualTo(sw.lat));
        expect(p.lat, lessThanOrEqualTo(ne.lat));
        expect(p.lng, greaterThanOrEqualTo(sw.lng));
        expect(p.lng, lessThanOrEqualTo(ne.lng));
      }
    });

    test('a single point yields a degenerate box', () {
      final (sw, ne) = Geo.bounds([swargate])!;
      expect(sw, swargate);
      expect(ne, swargate);
    });

    test('padding expands the box by roughly the requested distance', () {
      final tight = Geo.bounds([swargate, dadar])!;
      final padded = Geo.paddedBounds([swargate, dadar], padKm: 10)!;
      expect(padded.$1.lat, lessThan(tight.$1.lat));
      expect(padded.$2.lat, greaterThan(tight.$2.lat));

      final latPadKm = Geo.distanceKm(
        GeoPoint(tight.$1.lat, tight.$1.lng),
        GeoPoint(padded.$1.lat, tight.$1.lng),
      );
      expect(latPadKm, closeTo(10, 1.5));
    });

    test('padding a single point still produces a usable viewport', () {
      final padded = Geo.paddedBounds([swargate], padKm: 5)!;
      expect(padded.$2.lat, greaterThan(padded.$1.lat));
      expect(padded.$2.lng, greaterThan(padded.$1.lng));
    });
  });

  group('distance formatting', () {
    test('shows metres below one kilometre', () {
      expect(Geo.formatKm(0.42), '420 m');
      expect(Geo.formatKm(0.05), '50 m');
    });

    test('shows one decimal below ten kilometres', () {
      expect(Geo.formatKm(4.26), '4.3 km');
    });

    test('shows whole kilometres above ten', () {
      expect(Geo.formatKm(150.4), '150 km');
      expect(Geo.formatKm(842.7), '843 km');
    });
  });
}
