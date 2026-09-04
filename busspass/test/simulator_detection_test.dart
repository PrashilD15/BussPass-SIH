import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/services/bus_simulator.dart';
import 'package:busspass/core/services/transit_detection_service.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';

void main() {
  late TransitNetwork network;
  late BusSimulator simulator;

  setUpAll(() {
    network = TransitNetwork.fromJson(
      jsonDecode(File('assets/data/network.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    simulator = BusSimulator(network: network);
  });

  // A weekday mid-morning, when most services are running.
  final morning = DateTime(2026, 9, 3, 9, 30);

  group('simulator fleet', () {
    test('produces a fleet during service hours', () {
      final fleet = simulator.fleetAt(morning);
      expect(fleet, isNotEmpty);
    });

    test('every bus is honestly marked as simulated', () {
      // Presenting modelled positions as live telemetry would be dishonest, and
      // the UI relies on this flag to label them.
      for (final bus in simulator.fleetAt(morning)) {
        expect(bus.isSimulated, isTrue);
      }
    });

    test('the fleet is capped', () {
      final fleet = simulator.fleetAt(morning);
      expect(fleet.length, lessThanOrEqualTo(simulator.fleetCap));
    });

    test('bus ids are unique within a snapshot', () {
      final ids = simulator.fleetAt(morning).map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('registration plates look like real MSRTC plates', () {
      final pattern = RegExp(r'^MH\d{2}[A-Z]{2}\d{4}$');
      for (final bus in simulator.fleetAt(morning).take(50)) {
        expect(pattern.hasMatch(bus.id), isTrue,
            reason: '${bus.id} is not a plausible plate');
      }
    });

    test('every bus references a real route and service', () {
      for (final bus in simulator.fleetAt(morning)) {
        expect(network.routeById(bus.routeId), isNotNull);
      }
    });
  });

  group('determinism', () {
    test('the same instant always yields the same fleet', () {
      // The bug class this prevents: a bus teleporting on every rebuild.
      final first = simulator.fleetAt(morning);
      final second = simulator.fleetAt(morning);

      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].id, second[i].id);
        expect(first[i].lat, second[i].lat);
        expect(first[i].lng, second[i].lng);
        expect(first[i].travelledKm, second[i].travelledKm);
      }
    });

    test('a fresh simulator agrees with an existing one', () {
      final other = BusSimulator(network: network);
      final a = simulator.fleetAt(morning);
      final b = other.fleetAt(morning);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].id, b[i].id);
        expect(a[i].travelledKm, closeTo(b[i].travelledKm, 1e-9));
      }
    });

    test('a run keeps the same plate as it progresses', () {
      // A rider tracking one bus must not see its identity change.
      final early = simulator.fleetAt(DateTime(2026, 9, 3, 9, 0));
      if (early.isEmpty) return;
      final tracked = early.first;

      final later = simulator.fleetAt(DateTime(2026, 9, 3, 9, 20));
      final match = later.where((b) => b.id == tracked.id).toList();
      if (match.isEmpty) return; // run may have finished
      expect(match.first.routeId, tracked.routeId);
      expect(match.first.scheduledDeparture, tracked.scheduledDeparture);
    });
  });

  group('motion', () {
    test('buses advance along their route over time', () {
      final early = simulator.fleetAt(DateTime(2026, 9, 3, 9, 0));
      final moving = early
          .where((b) => b.state == BusState.inTransit && b.travelledKm > 1)
          .toList();
      if (moving.isEmpty) return;

      final tracked = moving.first;
      final later = simulator
          .fleetAt(DateTime(2026, 9, 3, 9, 25))
          .where((b) => b.id == tracked.id);
      if (later.isEmpty) return;

      expect(later.first.travelledKm, greaterThan(tracked.travelledKm),
          reason: 'a bus in transit did not move in 25 minutes');
    });

    test('travelled distance never exceeds the route length', () {
      for (final bus in simulator.fleetAt(morning)) {
        final route = network.routeById(bus.routeId)!;
        expect(bus.travelledKm, lessThanOrEqualTo(route.distanceKm + 0.5),
            reason: '${bus.id} is past the end of its route');
        expect(bus.travelledKm, greaterThanOrEqualTo(-0.01));
      }
    });

    test('every bus sits on its own route corridor', () {
      // The strongest correctness check available: a bus that drifts off its
      // polyline would break both the map and transit detection.
      for (final bus in simulator.fleetAt(morning).take(80)) {
        final route = network.routeById(bus.routeId)!;
        final projection =
            Geo.projectOnPolyline(bus.point, route.polyline);
        expect(projection, isNotNull);
        expect(projection!.offsetKm, lessThan(0.6),
            reason: '${bus.id} is ${projection.offsetKm.toStringAsFixed(2)} km '
                'off route ${route.id}');
      }
    });

    test('speed is plausible for a bus', () {
      for (final bus in simulator.fleetAt(morning)) {
        expect(bus.speedKmph, greaterThanOrEqualTo(0));
        expect(bus.speedKmph, lessThan(110),
            reason: '${bus.id} is doing ${bus.speedKmph} km/h');
      }
    });

    test('a stopped bus reports zero speed', () {
      final stopped = simulator
          .fleetAt(morning)
          .where((b) => b.state.isStopped || b.state == BusState.arrived);
      for (final bus in stopped) {
        expect(bus.speedKmph, 0);
      }
    });

    test('heading is a valid bearing', () {
      for (final bus in simulator.fleetAt(morning)) {
        expect(bus.heading, greaterThanOrEqualTo(0));
        expect(bus.heading, lessThan(360));
      }
    });

    test('next stop is a real sequence number on the route', () {
      for (final bus in simulator.fleetAt(morning)) {
        final route = network.routeById(bus.routeId)!;
        expect(route.stopRefBySeq(bus.nextStopSeq), isNotNull,
            reason: '${bus.id} points at stop seq ${bus.nextStopSeq}, which '
                'does not exist on ${route.id}');
      }
    });
  });

  group('states', () {
    test('rest halts occur on long routes', () {
      // Scan the day, because whether any bus is mid-halt depends on the moment.
      var sawBreak = false;
      for (var hour = 0; hour < 24 && !sawBreak; hour++) {
        final fleet = simulator.fleetAt(DateTime(2026, 9, 3, hour, 0));
        sawBreak = fleet.any((b) => b.state == BusState.onBreak);
      }
      expect(sawBreak, isTrue,
          reason: 'no bus took a rest halt anywhere in a 24-hour sweep');
    });

    test('buses dwell at intermediate stops', () {
      var sawDwell = false;
      for (var minute = 0; minute < 120 && !sawDwell; minute += 3) {
        final fleet = simulator
            .fleetAt(DateTime(2026, 9, 3, 9, 0).add(Duration(minutes: minute)));
        sawDwell = fleet.any((b) => b.state == BusState.atStop);
      }
      expect(sawDwell, isTrue, reason: 'no bus ever halted at a stop');
    });

    test('a bus at its origin has not moved', () {
      for (final bus in simulator
          .fleetAt(morning)
          .where((b) => b.state == BusState.atOrigin)) {
        expect(bus.travelledKm, 0);
        expect(bus.speedKmph, 0);
      }
    });

    test('an arrived bus is at the terminus', () {
      for (final bus in simulator
          .fleetAt(morning)
          .where((b) => b.state == BusState.arrived)) {
        final route = network.routeById(bus.routeId)!;
        expect(bus.travelledKm, closeTo(route.distanceKm, 0.5));
      }
    });
  });

  group('overnight services', () {
    test('a run that departed yesterday is still tracked after midnight', () {
      // The subtlety minute-of-day arithmetic alone would miss: an overnight
      // Nagpur–Mumbai that left at 21:00 is on the road at 04:00.
      final earlyHours = simulator.fleetAt(DateTime(2026, 9, 4, 4, 0));
      expect(earlyHours, isNotEmpty,
          reason: 'no buses on the road at 04:00 — overnight runs are being '
              'dropped at the date boundary');

      final longHaul = earlyHours.where((b) {
        final route = network.routeById(b.routeId)!;
        return route.distanceKm > 300;
      });
      expect(longHaul, isNotEmpty);
    });

    test('a scheduled departure precedes the position report', () {
      for (final bus in simulator.fleetAt(DateTime(2026, 9, 4, 4, 0))) {
        expect(bus.scheduledDeparture.isAfter(bus.updatedAt), isFalse);
      }
    });
  });

  group('occupancy', () {
    test('passenger count is within capacity bounds', () {
      for (final bus in simulator.fleetAt(morning)) {
        final seats = ServiceClassCatalog.byKey(bus.busType).seats;
        expect(bus.passengerCount, isNotNull);
        expect(bus.passengerCount!, greaterThanOrEqualTo(0));
        expect(bus.passengerCount!, lessThanOrEqualTo((seats * 1.2).ceil()),
            reason: '${bus.id} carries ${bus.passengerCount} in $seats seats');
      }
    });

    test('occupancy is stable for a given bus', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      final again = simulator.fleetAt(morning);
      expect(fleet.first.passengerCount, again.first.passengerCount);
    });
  });

  group('queries', () {
    test('buses can be filtered by route', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      final routeId = fleet.first.routeId;
      final onRoute = simulator.busesOnRoute(routeId, morning);
      expect(onRoute, isNotEmpty);
      for (final bus in onRoute) {
        expect(bus.routeId, routeId);
      }
    });

    test('nearest bus respects the radius', () {
      const pune = GeoPoint(18.5013, 73.8567);
      final near = simulator.nearestBus(pune, morning, radiusKm: 30);
      if (near == null) return;
      expect(Geo.distanceKm(pune, near.point), lessThanOrEqualTo(30));
    });

    test('nearest bus returns null when nothing is close', () {
      // Middle of the Arabian Sea.
      const offshore = GeoPoint(16.0, 68.0);
      expect(simulator.nearestBus(offshore, morning, radiusKm: 5), isNull);
    });
  });

  group('freshness reporting', () {
    test('a just-reported position reads as live', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      expect(fleet.first.isFreshAt(morning), isTrue);
      expect(fleet.first.freshnessLabel(morning), 'Live');
    });

    test('a stale position is reported as stale, not hidden', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      final later = morning.add(const Duration(minutes: 20));
      expect(fleet.first.isFreshAt(later), isFalse);
      expect(fleet.first.freshnessLabel(later), contains('20 min ago'));
    });

    test('a very old position reports signal loss', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      expect(
        fleet.first.freshnessLabel(morning.add(const Duration(hours: 3))),
        'Signal lost',
      );
    });
  });

  group('RTDB serialisation', () {
    test('round-trips through the wire format', () {
      final fleet = simulator.fleetAt(morning);
      if (fleet.isEmpty) return;
      final original = fleet.first;

      final decoded = LiveBus.fromRtdb(original.id, original.toRtdb());
      expect(decoded, isNotNull);
      expect(decoded!.id, original.id);
      expect(decoded.routeId, original.routeId);
      expect(decoded.lat, closeTo(original.lat, 1e-9));
      expect(decoded.lng, closeTo(original.lng, 1e-9));
      expect(decoded.travelledKm, closeTo(original.travelledKm, 1e-9));
      expect(decoded.state, original.state);
    });

    test('a malformed node yields null rather than throwing', () {
      // One bad bus must not blank the whole map.
      expect(LiveBus.fromRtdb('MH12AB1234', {}), isNull);
      expect(LiveBus.fromRtdb('MH12AB1234', {'lat': 18.5}), isNull);
      expect(
        LiveBus.fromRtdb('MH12AB1234', {'lat': 'oops', 'lng': 73.8}),
        isNull,
      );
    });

    test('a minimal valid node parses', () {
      final bus = LiveBus.fromRtdb('MH12AB1234', {
        'lat': 18.5013,
        'lng': 73.8567,
      });
      expect(bus, isNotNull);
      expect(bus!.speedKmph, 0);
      expect(bus.busType, 'Ordinary');
    });
  });

  group('position trail', () {
    test('is empty to begin with', () {
      final trail = PositionTrail();
      expect(trail.isEmpty, isTrue);
      expect(trail.averageSpeedKmph, 0);
      expect(trail.distanceKm, 0);
    });

    test('drops samples outside its window', () {
      final trail = PositionTrail(window: const Duration(minutes: 5));
      final start = DateTime(2026, 9, 3, 9, 0);

      for (var i = 0; i < 20; i++) {
        trail.add(TrailPoint(
          point: GeoPoint(18.5 + i * 0.001, 73.8),
          speedKmph: 40,
          heading: 0,
          at: start.add(Duration(minutes: i)),
        ));
      }
      // Only the last 5 minutes plus the boundary sample survive.
      expect(trail.points.length, lessThanOrEqualTo(6));
      expect(trail.latest!.at, start.add(const Duration(minutes: 19)));
    });

    test('sustained-above resets on a single slow sample', () {
      // A bus stopped at a traffic light must reset the streak, exactly as a
      // pedestrian would.
      final trail = PositionTrail();
      final start = DateTime(2026, 9, 3, 9, 0);

      for (var i = 0; i < 5; i++) {
        trail.add(TrailPoint(
          point: GeoPoint(18.5, 73.8),
          speedKmph: 40,
          heading: 0,
          at: start.add(Duration(minutes: i)),
        ));
      }
      expect(trail.sustainedAbove(15).inMinutes, 4);

      trail.add(TrailPoint(
        point: const GeoPoint(18.5, 73.8),
        speedKmph: 2,
        heading: 0,
        at: start.add(const Duration(minutes: 5)),
      ));
      expect(trail.sustainedAbove(15), Duration.zero);
    });

    test('mean heading uses a circular mean', () {
      // The bug this guards: averaging 350 and 10 arithmetically gives 180,
      // the exact opposite of the truth.
      final trail = PositionTrail();
      final at = DateTime(2026, 9, 3, 9, 0);
      for (final heading in [350.0, 10.0]) {
        trail.add(TrailPoint(
          point: const GeoPoint(18.5, 73.8),
          speedKmph: 40,
          heading: heading,
          at: at,
        ));
      }
      final mean = trail.meanHeading;
      expect(mean < 5 || mean > 355, isTrue,
          reason: 'circular mean of 350 and 10 should be ~0, got $mean');
    });

    test('accumulates distance along the trail', () {
      final trail = PositionTrail();
      final at = DateTime(2026, 9, 3, 9, 0);
      trail.add(TrailPoint(
          point: const GeoPoint(18.5, 73.8),
          speedKmph: 40, heading: 0, at: at));
      trail.add(TrailPoint(
          point: const GeoPoint(18.6, 73.8),
          speedKmph: 40, heading: 0,
          at: at.add(const Duration(minutes: 1))));
      expect(trail.distanceKm, closeTo(11.1, 0.3));
    });
  });

  group('transit detection', () {
    late TransitDetector detector;

    setUp(() {
      detector = TransitDetector(network: network);
    });

    /// Feed a sequence of samples at one-minute intervals.
    TransitDetection feed({
      required GeoPoint point,
      required double speedKmph,
      required double heading,
      required int minutes,
      List<LiveBus> fleet = const [],
      DateTime? from,
    }) {
      final start = from ?? DateTime(2026, 9, 3, 9, 0);
      var result = TransitDetection.unknown;
      for (var i = 0; i <= minutes; i++) {
        result = detector.update(
          point: point,
          speedKmph: speedKmph,
          heading: heading,
          at: start.add(Duration(minutes: i)),
          fleet: fleet,
        );
      }
      return result;
    }

    test('a short trail is unknown, not asserted', () {
      final result = detector.update(
        point: const GeoPoint(18.5013, 73.8567),
        speedKmph: 45,
        heading: 300,
        at: DateTime(2026, 9, 3, 9, 0),
        fleet: const [],
      );
      expect(result.status, TransitStatus.unknown);
    });

    test('a stationary rider is detected as stationary', () {
      final result = feed(
        point: const GeoPoint(18.5013, 73.8567),
        speedKmph: 1,
        heading: 0,
        minutes: 5,
      );
      expect(result.status, TransitStatus.stationary);
    });

    test('walking speed does not count as a vehicle', () {
      final result = feed(
        point: const GeoPoint(18.5013, 73.8567),
        speedKmph: 5,
        heading: 90,
        minutes: 5,
      );
      expect(result.status, TransitStatus.stationary);
    });

    test('moving fast off any corridor is a private vehicle', () {
      // Well away from any MSRTC route.
      final result = feed(
        point: const GeoPoint(21.9, 80.7),
        speedKmph: 70,
        heading: 90,
        minutes: 5,
      );
      expect(result.status, TransitStatus.privateVehicle);
    });

    test('on a corridor with no bus reporting prompts the rider', () {
      // Exactly on a route stop, so corridor offset is ~0.
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final onRoute = route.stops[1].point;

      final result = feed(
        point: onRoute,
        speedKmph: 50,
        heading: Geo.bearing(route.stops[1].point, route.stops[2].point),
        minutes: 5,
      );
      expect(result.status, TransitStatus.possiblyOnBus);
      expect(result.routeId, isNotNull);
    });

    test('a matching bus held long enough confirms boarding', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final onRoute = route.stops[1].point;
      final heading =
          Geo.bearing(route.stops[1].point, route.stops[2].point);
      final start = DateTime(2026, 9, 3, 9, 0);

      // A bus co-located with the rider, re-reporting each minute so it never
      // goes stale.
      List<LiveBus> fleetAt(DateTime at) => [
            LiveBus(
              id: 'MH12AB1234',
              routeId: route.id,
              serviceId: 'svc-test',
              busType: 'Ordinary',
              lat: onRoute.lat,
              lng: onRoute.lng,
              speedKmph: 50,
              heading: heading,
              travelledKm: route.stops[1].cumKm,
              nextStopSeq: route.stops[2].seq,
              state: BusState.inTransit,
              updatedAt: at,
              scheduledDeparture: start,
            ),
          ];

      var result = TransitDetection.unknown;
      for (var i = 0; i <= 6; i++) {
        final at = start.add(Duration(minutes: i));
        result = detector.update(
          point: onRoute,
          speedKmph: 50,
          heading: heading,
          at: at,
          fleet: fleetAt(at),
        );
      }

      expect(result.status, TransitStatus.onBoard);
      expect(result.bus?.id, 'MH12AB1234');
      expect(result.confidence, greaterThan(0.5));
    });

    test('a bus on the opposite carriageway is rejected on heading', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final onRoute = route.stops[1].point;
      final heading =
          Geo.bearing(route.stops[1].point, route.stops[2].point);
      final start = DateTime(2026, 9, 3, 9, 0);

      // Same place, opposite direction — a bus that legitimately passes within
      // 100 m but is not the one the rider is on.
      List<LiveBus> fleetAt(DateTime at) => [
            LiveBus(
              id: 'MH12ZZ9999',
              routeId: route.id,
              serviceId: 'svc-opposite',
              busType: 'Ordinary',
              lat: onRoute.lat,
              lng: onRoute.lng,
              speedKmph: 50,
              heading: (heading + 180) % 360,
              travelledKm: route.stops[1].cumKm,
              nextStopSeq: route.stops[0].seq,
              state: BusState.inTransit,
              updatedAt: at,
              scheduledDeparture: start,
            ),
          ];

      var result = TransitDetection.unknown;
      for (var i = 0; i <= 6; i++) {
        final at = start.add(Duration(minutes: i));
        result = detector.update(
          point: onRoute,
          speedKmph: 50,
          heading: heading,
          at: at,
          fleet: fleetAt(at),
        );
      }
      expect(result.status, isNot(TransitStatus.onBoard));
    });

    test('a stale bus report cannot confirm a match', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final onRoute = route.stops[1].point;
      final start = DateTime(2026, 9, 3, 9, 0);

      // Reported once, then never again — the bus could be kilometres away.
      final stale = [
        LiveBus(
          id: 'MH12AB1234',
          routeId: route.id,
          serviceId: 'svc-stale',
          busType: 'Ordinary',
          lat: onRoute.lat,
          lng: onRoute.lng,
          speedKmph: 50,
          heading: 0,
          travelledKm: 0,
          nextStopSeq: 2,
          state: BusState.inTransit,
          updatedAt: start.subtract(const Duration(minutes: 30)),
          scheduledDeparture: start,
        ),
      ];

      final result = feed(
        point: onRoute,
        speedKmph: 50,
        heading: 0,
        minutes: 6,
        fleet: stale,
        from: start,
      );
      expect(result.status, isNot(TransitStatus.onBoard));
    });

    test('reset clears all state', () {
      feed(
        point: const GeoPoint(18.5013, 73.8567),
        speedKmph: 45,
        heading: 300,
        minutes: 5,
      );
      detector.reset();
      expect(detector.trail.isEmpty, isTrue);
    });
  });

  group('journey progress', () {
    test('is null for an unprojectable route', () {
      final route = network.routes.first;
      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: route.stops.first.point,
        boardSeq: 1,
        alightSeq: 999, // does not exist
      );
      expect(progress, isNull);
    });

    test('is zero at the boarding stop', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: route.stops.first.point,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      expect(progress.fraction, closeTo(0, 0.02));
      expect(progress.travelledKm, closeTo(0, 0.5));
      expect(progress.remainingKm, closeTo(route.distanceKm, 1.0));
    });

    test('is complete at the alighting stop', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: route.stops.last.point,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      expect(progress.fraction, closeTo(1, 0.02));
      expect(progress.remainingKm, closeTo(0, 1.0));
      expect(progress.nextStop, isNull);
    });

    test('reports the correct next stop mid-route', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 4);
      // Just past the second stop.
      final justPast = route.pointAtRoadKm(route.stops[1].cumKm + 0.5);

      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: justPast,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      expect(progress.nextStop?.stopId, route.stops[2].stopId);
      expect(progress.remainingStops, route.stops.length - 2);
    });

    test('progress is monotonic along the route', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 4);
      var previous = -1.0;
      for (var fraction = 0.0; fraction <= 1.0; fraction += 0.1) {
        final point = route.pointAtRoadKm(route.distanceKm * fraction);
        final progress = JourneyProgress.compute(
          route: route,
          riderPoint: point,
          boardSeq: route.stops.first.seq,
          alightSeq: route.stops.last.seq,
        )!;
        expect(progress.fraction, greaterThanOrEqualTo(previous));
        previous = progress.fraction;
      }
    });

    test('travelled plus remaining equals the segment length', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 4);
      final point = route.pointAtRoadKm(route.distanceKm * 0.4);
      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: point,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      expect(progress.travelledKm + progress.remainingKm,
          closeTo(route.distanceKm, 1.0));
    });

    test('works for a partial segment, not just terminus to terminus', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 4);
      final board = route.stops[1];
      final alight = route.stops[2];
      final midKm = (board.cumKm + alight.cumKm) / 2;

      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: route.pointAtRoadKm(midKm),
        boardSeq: board.seq,
        alightSeq: alight.seq,
      )!;
      expect(progress.fraction, closeTo(0.5, 0.1));
    });

    test('flags approach to the destination', () {
      final route = network.routes.firstWhere((r) => r.distanceKm > 50);
      final nearEnd = route.pointAtRoadKm(route.distanceKm - 1);
      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: nearEnd,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      expect(progress.isApproachingDestination, isTrue);
    });

    test('handles a reverse-direction journey', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 4);
      // Travelling from the last stop back to the first.
      final quarterFromEnd = route.pointAtRoadKm(route.distanceKm * 0.75);

      final progress = JourneyProgress.compute(
        route: route,
        riderPoint: quarterFromEnd,
        boardSeq: route.stops.last.seq,
        alightSeq: route.stops.first.seq,
      )!;
      expect(progress.fraction, closeTo(0.25, 0.1));
      expect(progress.travelledKm, greaterThan(0));
      expect(progress.remainingKm, greaterThan(0));
    });

    test('reports how far off-route the rider is', () {
      final route = network.routes.firstWhere((r) => r.stops.length >= 3);
      final onRoute = route.stops[1].point;
      final offRoute = GeoPoint(onRoute.lat + 0.15, onRoute.lng + 0.15);

      final on = JourneyProgress.compute(
        route: route,
        riderPoint: onRoute,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;
      final off = JourneyProgress.compute(
        route: route,
        riderPoint: offRoute,
        boardSeq: route.stops.first.seq,
        alightSeq: route.stops.last.seq,
      )!;

      expect(on.offRouteKm, lessThan(0.1));
      expect(off.offRouteKm, greaterThan(5));
    });
  });

  group('detection service', () {
    test('throttles to the configured sample interval', () async {
      final service = TransitDetectionService(
        network: network,
        config: const TransitDetectionConfig(
          sampleInterval: Duration(seconds: 30),
        ),
      );
      addTearDown(service.dispose);

      final emitted = <TransitDetection>[];
      final subscription = service.detections.listen(emitted.add);
      addTearDown(subscription.cancel);

      final start = DateTime(2026, 9, 3, 9, 0);
      // Five samples five seconds apart span 20 s, which is inside the 30 s
      // interval, so only the first is admitted.
      for (var i = 0; i < 5; i++) {
        service.addPosition(
          point: const GeoPoint(18.5013, 73.8567),
          speedKmph: 45,
          heading: 300,
          at: start.add(Duration(seconds: i * 5)),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(emitted.length, 1);
    });

    test('accepts samples at or beyond the interval', () async {
      final service = TransitDetectionService(
        network: network,
        config: const TransitDetectionConfig(
          sampleInterval: Duration(seconds: 30),
        ),
      );
      addTearDown(service.dispose);

      final emitted = <TransitDetection>[];
      final subscription = service.detections.listen(emitted.add);
      addTearDown(subscription.cancel);

      final start = DateTime(2026, 9, 3, 9, 0);
      for (var i = 0; i < 4; i++) {
        service.addPosition(
          point: const GeoPoint(18.5013, 73.8567),
          speedKmph: 45,
          heading: 300,
          at: start.add(Duration(seconds: i * 40)),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(emitted.length, 4);
    });
  });
}
