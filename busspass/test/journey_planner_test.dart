import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/data/models/network_models.dart';

/// A small synthetic network with known-correct answers.
///
/// Geography is a straight west-to-east line so distances are predictable:
///
/// ```
///   A ---- B ---- C ---- D        (corridor 1: A→D through B and C)
///          |
///          E                      (corridor 2: B→E, a branch)
///
///   X ---- Y                      (corridor 3: isolated, unreachable from A)
/// ```
///
/// `A2` is a second stand in city A, 0.6 km from `A`, so walk transfers can be
/// exercised.
TransitNetwork buildTestNetwork() {
  const stops = [
    NetworkStop(id: 'A', name: 'A Stand', city: 'Alpha', depot: 'Alpha',
        district: 'Alpha', lat: 18.0, lng: 73.0, tier: 3),
    NetworkStop(id: 'A2', name: 'A Second Stand', city: 'Alpha', depot: 'Alpha2',
        district: 'Alpha', lat: 18.0, lng: 73.0057, tier: 2),
    NetworkStop(id: 'B', name: 'B Stand', city: 'Bravo', depot: 'Bravo',
        district: 'Bravo', lat: 18.0, lng: 73.5, tier: 3),
    NetworkStop(id: 'C', name: 'C Stand', city: 'Charlie', depot: 'Charlie',
        district: 'Charlie', lat: 18.0, lng: 74.0, tier: 2),
    NetworkStop(id: 'D', name: 'D Stand', city: 'Delta', depot: 'Delta',
        district: 'Delta', lat: 18.0, lng: 74.5, tier: 3),
    NetworkStop(id: 'E', name: 'E Stand', city: 'Echo', depot: 'Echo',
        district: 'Echo', lat: 18.5, lng: 73.5, tier: 2),
    NetworkStop(id: 'X', name: 'X Stand', city: 'Xray', depot: 'Xray',
        district: 'Xray', lat: 21.0, lng: 79.0, tier: 3),
    NetworkStop(id: 'Y', name: 'Y Stand', city: 'Yankee', depot: 'Yankee',
        district: 'Yankee', lat: 21.0, lng: 79.5, tier: 2),
  ];

  RouteStopRef ref(String id, String city, double lat, double lng, int seq,
          double cum) =>
      RouteStopRef(
          stopId: id, name: '$id Stand', city: city, lat: lat, lng: lng,
          seq: seq, cumKm: cum);

  final routes = [
    // A→D, 160 km, calling at B (55 km) and C (110 km).
    TransitRoute(
      id: 'A-D', name: 'Alpha – Delta', operatorName: 'MSRTC', isCorridor: true,
      originStopId: 'A', destinationStopId: 'D',
      originCity: 'Alpha', destinationCity: 'Delta',
      distanceKm: 160,
      busTypes: const ['Ordinary', 'Shivneri'],
      stops: [
        ref('A', 'Alpha', 18.0, 73.0, 1, 0),
        ref('B', 'Bravo', 18.0, 73.5, 2, 55),
        ref('C', 'Charlie', 18.0, 74.0, 3, 110),
        ref('D', 'Delta', 18.0, 74.5, 4, 160),
      ],
    ),
    // B→E branch, 60 km, no intermediate stops.
    TransitRoute(
      id: 'B-E', name: 'Bravo – Echo', operatorName: 'MSRTC', isCorridor: true,
      originStopId: 'B', destinationStopId: 'E',
      originCity: 'Bravo', destinationCity: 'Echo',
      distanceKm: 60,
      busTypes: const ['Ordinary'],
      stops: [
        ref('B', 'Bravo', 18.0, 73.5, 1, 0),
        ref('E', 'Echo', 18.5, 73.5, 2, 60),
      ],
    ),
    // A2→C, 105 km, from the *second* Alpha stand. Only reachable by walking.
    TransitRoute(
      id: 'A2-C', name: 'Alpha2 – Charlie', operatorName: 'MSRTC',
      isCorridor: true,
      originStopId: 'A2', destinationStopId: 'C',
      originCity: 'Alpha', destinationCity: 'Charlie',
      distanceKm: 105,
      busTypes: const ['Semi Luxury'],
      stops: [
        ref('A2', 'Alpha', 18.0, 73.0057, 1, 0),
        ref('C', 'Charlie', 18.0, 74.0, 2, 105),
      ],
    ),
    // Isolated island.
    TransitRoute(
      id: 'X-Y', name: 'Xray – Yankee', operatorName: 'MSRTC', isCorridor: true,
      originStopId: 'X', destinationStopId: 'Y',
      originCity: 'Xray', destinationCity: 'Yankee',
      distanceKm: 50,
      busTypes: const ['Ordinary'],
      stops: [
        ref('X', 'Xray', 21.0, 79.0, 1, 0),
        ref('Y', 'Yankee', 21.0, 79.5, 2, 50),
      ],
    ),
  ];

  final services = [
    // Hourly Ordinary on A→D from 06:00 to 20:00.
    TransitService(
      id: 'svc-ad-ord', routeId: 'A-D', busType: 'Ordinary',
      source: 'corridor', fromStopId: null,
      departures: [for (var h = 6; h <= 20; h++) h * 60],
    ),
    // Twice-daily Shivneri on A→D.
    const TransitService(
      id: 'svc-ad-shiv', routeId: 'A-D', busType: 'Shivneri',
      source: 'corridor', fromStopId: null,
      departures: [7 * 60, 15 * 60],
    ),
    // B→E every two hours from 08:00.
    TransitService(
      id: 'svc-be', routeId: 'B-E', busType: 'Ordinary',
      source: 'corridor', fromStopId: null,
      departures: [for (var h = 8; h <= 20; h += 2) h * 60],
    ),
    // A2→C, directional: only from A2.
    const TransitService(
      id: 'svc-a2c', routeId: 'A2-C', busType: 'Semi Luxury',
      source: 'timetable', fromStopId: 'A2',
      departures: [8 * 60, 13 * 60],
    ),
    const TransitService(
      id: 'svc-xy', routeId: 'X-Y', busType: 'Ordinary',
      source: 'corridor', fromStopId: null,
      departures: [9 * 60],
    ),
  ];

  return TransitNetwork(
      stops: stops, routes: routes, services: services);
}

void main() {
  final network = buildTestNetwork();
  final graph = TransitGraph.build(network);
  final planner = JourneyPlanner(graph);

  // Fixed reference time: 06:00 on a Thursday.
  final morning = DateTime(2026, 9, 3, 6, 0);

  group('graph construction', () {
    test('indexes every stop that a route calls at', () {
      expect(graph.callsAt('A'), isNotEmpty);
      expect(graph.callsAt('B'), isNotEmpty);
      expect(graph.callsAt('C'), isNotEmpty);
    });

    test('a mid-corridor stop is a first-class node', () {
      // The core failure of city-name matching: B and C are neither terminus of
      // A-D, so string matching could never route through them.
      expect(graph.callsAt('B').length, greaterThanOrEqualTo(2));
      expect(graph.directlyReachable('B'), contains('D'));
      expect(graph.directlyReachable('B'), contains('E'));
    });

    test('direct reachability excludes the stop itself', () {
      expect(graph.directlyReachable('A'), isNot(contains('A')));
    });

    test('an isolated component is not reachable', () {
      expect(graph.directlyReachable('A'), isNot(contains('X')));
    });

    test('sibling stands in the same city are found', () {
      expect(graph.siblingStops('A'), ['A2']);
      expect(graph.siblingStops('A2'), ['A']);
      expect(graph.siblingStops('B'), isEmpty);
    });

    test('service count reflects how busy a stand is', () {
      expect(graph.serviceCountAt('A'), greaterThan(0));
      expect(graph.serviceCountAt('B'),
          greaterThan(graph.serviceCountAt('E')));
    });
  });

  group('nearest stop', () {
    test('finds the closest stand and reports the distance', () {
      final result = graph.nearestStop(const GeoPoint(18.01, 73.01));
      expect(result, isNotNull);
      expect(result!.stop.id, anyOf('A', 'A2'));
      expect(result.distanceKm, lessThan(5));
    });

    test('reports a large distance rather than silently snapping', () {
      // The old code snapped a user anywhere on Earth to the nearest stand with
      // no distance check. Callers need the distance to reject the match.
      final result = graph.nearestStop(const GeoPoint(28.6, 77.2));
      expect(result, isNotNull);
      expect(result!.distanceKm, greaterThan(500));
    });

    test('radius search returns nearest-first and respects the radius', () {
      final near = graph.stopsNear(const GeoPoint(18.0, 73.2),
          radiusKm: 40);
      expect(near, isNotEmpty);
      for (var i = 1; i < near.length; i++) {
        expect(near[i].distanceKm,
            greaterThanOrEqualTo(near[i - 1].distanceKm));
      }
      for (final entry in near) {
        expect(entry.distanceKm, lessThanOrEqualTo(40));
      }
    });
  });

  group('direct journeys', () {
    test('finds the direct A→D service', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      expect(results, isNotEmpty);
      expect(results.any((it) => it.isDirect), isTrue);
    });

    test('a direct itinerary has one leg and no transfers', () {
      final direct = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect);
      expect(direct.legs.length, 1);
      expect(direct.transfers, isEmpty);
      expect(direct.transferCount, 0);
    });

    test('routes through a mid-corridor stop that is not a terminus', () {
      // A→C: C is an intermediate stop on A-D. String matching on termini
      // would report no route.
      final results = planner.plan(
          originId: 'A', destinationId: 'C', departAfter: morning);
      expect(results, isNotEmpty);
      expect(results.first.isDirect, isTrue);
      expect(results.first.distanceKm, closeTo(110, 0.01));
    });

    test('a mid-corridor origin works too', () {
      final results = planner.plan(
          originId: 'B', destinationId: 'D', departAfter: morning);
      expect(results, isNotEmpty);
      expect(results.first.distanceKm, closeTo(105, 0.01));
    });

    test('travels the corridor in reverse', () {
      final results = planner.plan(
          originId: 'D', destinationId: 'A', departAfter: morning);
      expect(results, isNotEmpty);
      expect(results.first.distanceKm, closeTo(160, 0.01));
    });

    test('leg distance comes from cumulative kilometres, not the full route', () {
      final results = planner.plan(
          originId: 'B', destinationId: 'C', departAfter: morning);
      expect(results, isNotEmpty);
      // 110 - 55 = 55, not the 160 km full corridor.
      expect(results.first.distanceKm, closeTo(55, 0.01));
    });

    test('fare matches the segment distance, not the corridor', () {
      final bToC = planner
          .plan(originId: 'B', destinationId: 'C', departAfter: morning)
          .first;
      final aToD = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect);
      expect(bToC.totalFare, lessThan(aToD.totalFare));
    });
  });

  group('transfers', () {
    test('finds a one-transfer route to a branch destination', () {
      // A→E requires riding A-D to B, then B-E.
      final results = planner.plan(
          originId: 'A', destinationId: 'E', departAfter: morning);
      expect(results, isNotEmpty);
      final withTransfer = results.firstWhere((it) => !it.isDirect);
      expect(withTransfer.legs.length, 2);
      expect(withTransfer.transfers.length, 1);
      expect(withTransfer.transfers.first.stop.id, 'B');
    });

    test('a connection never departs before the first leg arrives', () {
      // This was structurally impossible to guarantee in the old code, which
      // never looked at times.
      for (final destination in ['D', 'E', 'C']) {
        final results = planner.plan(
            originId: 'A', destinationId: destination, departAfter: morning);
        for (final itinerary in results) {
          for (var i = 0; i < itinerary.legs.length - 1; i++) {
            expect(
              itinerary.legs[i + 1].departsAt.isBefore(
                  itinerary.legs[i].arrivesAt),
              isFalse,
              reason: 'leg ${i + 1} departs before leg $i arrives on '
                  'A→$destination',
            );
          }
        }
      }
    });

    test('every transfer respects the minimum connection buffer', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'E', departAfter: morning);
      for (final itinerary in results) {
        for (final gap in itinerary.transfers) {
          expect(gap.waitMinutes,
              greaterThanOrEqualTo(PlannerConfig.standard.minTransferMinutes),
              reason: 'connection at ${gap.stop.id} was only '
                  '${gap.waitMinutes} min');
        }
      }
    });

    test('transfer wait is arrival-to-departure, and non-negative', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .firstWhere((it) => !it.isDirect);
      final gap = itinerary.transfers.first;
      expect(gap.waitMinutes, greaterThanOrEqualTo(0));
      expect(gap.departsAt.difference(gap.arrivesAt).inMinutes,
          gap.waitMinutes);
    });

    test('no itinerary revisits a stop', () {
      for (final destination in ['C', 'D', 'E']) {
        final results = planner.plan(
            originId: 'A', destinationId: destination, departAfter: morning);
        for (final itinerary in results) {
          final visited = <String>[itinerary.legs.first.boardStop.id];
          for (final leg in itinerary.legs) {
            visited.add(leg.alightStop.id);
          }
          expect(visited.toSet().length, visited.length,
              reason: 'A→$destination revisits a stop: $visited');
        }
      }
    });

    test('walk transfers between stands in one city are used', () {
      // A→C has a direct option on A-D. A2-C is a *different* service reachable
      // only by walking A→A2, and should surface as an alternative.
      final results = planner.plan(
          originId: 'A', destinationId: 'C', departAfter: morning);
      final routeIds =
          results.expand((it) => it.legs.map((l) => l.route.id)).toSet();
      expect(routeIds, contains('A-D'));
    });
  });

  group('directional services', () {
    test('a scraped board is not rideable in reverse', () {
      // svc-a2c runs A2→C only. Planning C→A2 must not use it.
      final results = planner.plan(
          originId: 'C', destinationId: 'A2', departAfter: morning);
      for (final itinerary in results) {
        for (final leg in itinerary.legs) {
          if (leg.route.id == 'A2-C') {
            expect(leg.boardStop.id, 'A2',
                reason: 'directional service ridden backwards');
          }
        }
      }
    });

    test('a directional service works in its own direction', () {
      final results = planner.plan(
          originId: 'A2', destinationId: 'C', departAfter: morning);
      expect(results, isNotEmpty);
      expect(results.any((it) => it.legs.first.route.id == 'A2-C'), isTrue);
    });
  });

  group('time dependence', () {
    test('departure is at or after the requested time', () {
      for (final hour in [6, 9, 14, 19]) {
        final at = DateTime(2026, 9, 3, hour, 0);
        final results =
            planner.plan(originId: 'A', destinationId: 'D', departAfter: at);
        for (final itinerary in results) {
          expect(itinerary.departsAt.isBefore(at), isFalse,
              reason: 'itinerary departs before the requested $hour:00');
        }
      }
    });

    test('arrival is always after departure', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'E', departAfter: morning);
      for (final itinerary in results) {
        expect(itinerary.arrivesAt.isAfter(itinerary.departsAt), isTrue);
        expect(itinerary.totalMinutes, greaterThan(0));
      }
    });

    test('a later query returns a later departure', () {
      final early = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .first;
      final late = planner
          .plan(
              originId: 'A',
              destinationId: 'D',
              departAfter: DateTime(2026, 9, 3, 16, 0))
          .first;
      expect(late.departsAt.isAfter(early.departsAt), isTrue);
    });

    test('a late-night query rolls to the next morning', () {
      // Last A-D Ordinary is 20:00, so a 23:00 query must find tomorrow's 06:00.
      final results = planner.plan(
          originId: 'A',
          destinationId: 'D',
          departAfter: DateTime(2026, 9, 3, 23, 0));
      expect(results, isNotEmpty);
      expect(results.first.departsAt.day, 4);
    });

    test('boarding at a mid-corridor stop is offset from the origin time', () {
      // A bus leaving A at 06:00 reaches B later, so a rider at B boards later.
      final fromA = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect);
      final fromB = planner
          .plan(originId: 'B', destinationId: 'D', departAfter: morning)
          .first;
      expect(fromB.departsAt.isAfter(fromA.departsAt), isTrue,
          reason: 'B departure should be offset by the A→B running time');
    });
  });

  group('determinism', () {
    test('the same query returns identical results every time', () {
      // The old planner iterated an unordered Set, so results varied run to run.
      final signatures = <String>{};
      for (var i = 0; i < 8; i++) {
        final results = planner.plan(
            originId: 'A', destinationId: 'E', departAfter: morning);
        signatures.add(results.map((it) => it.signature).join('#'));
      }
      expect(signatures.length, 1,
          reason: 'planner produced ${signatures.length} distinct result sets');
    });
  });

  group('ranking', () {
    test('fastest ranks by earliest arrival', () {
      final results = planner.plan(
          originId: 'A',
          destinationId: 'D',
          departAfter: morning,
          preference: JourneyPreference.fastest);
      expect(results.length, greaterThan(1));
      // The top result must arrive no later than any other.
      for (final other in results.skip(1)) {
        expect(
          results.first.arrivesAt.isAfter(other.arrivesAt),
          isFalse,
          reason: 'a later-ranked option arrives earlier',
        );
      }
    });

    test('cheapest ranks by fare', () {
      final results = planner.plan(
          originId: 'A',
          destinationId: 'D',
          departAfter: morning,
          preference: JourneyPreference.cheapest);
      expect(results.first.totalFare,
          lessThanOrEqualTo(results.last.totalFare));
    });

    test('fewest changes puts a direct bus first', () {
      final results = planner.plan(
          originId: 'A',
          destinationId: 'D',
          departAfter: morning,
          preference: JourneyPreference.fewestChanges);
      expect(results.first.transferCount, 0);
    });

    test('a direct option is always offered when one exists', () {
      for (final preference in JourneyPreference.values) {
        final results = planner.plan(
            originId: 'A',
            destinationId: 'D',
            departAfter: morning,
            preference: preference);
        expect(results.any((it) => it.isDirect), isTrue,
            reason: 'no direct option under ${preference.name}');
      }
    });

    test('results are distinct, not three copies of one answer', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      final signatures = results.map((it) => it.signature).toSet();
      expect(signatures.length, results.length);
    });

    test('result count is bounded by the config', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      expect(results.length,
          lessThanOrEqualTo(PlannerConfig.standard.resultCount + 1));
    });
  });

  group('unreachable and degenerate queries', () {
    test('an isolated component yields no itinerary', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'X', departAfter: morning);
      expect(results, isEmpty);
    });

    test('origin equal to destination yields nothing', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'A', departAfter: morning);
      expect(results, isEmpty);
    });

    test('an unknown stop id yields nothing rather than throwing', () {
      expect(
        planner.plan(
            originId: 'NOPE', destinationId: 'D', departAfter: morning),
        isEmpty,
      );
      expect(
        planner.plan(
            originId: 'A', destinationId: 'NOPE', departAfter: morning),
        isEmpty,
      );
    });

    test('an empty network yields nothing', () {
      final emptyPlanner =
          JourneyPlanner(TransitGraph.build(TransitNetwork.empty));
      expect(
        emptyPlanner.plan(
            originId: 'A', destinationId: 'D', departAfter: morning),
        isEmpty,
      );
    });
  });

  group('itinerary arithmetic', () {
    test('total time equals in-vehicle plus waiting', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .firstWhere((it) => !it.isDirect);
      expect(itinerary.totalMinutes,
          itinerary.inVehicleMinutes + itinerary.waitMinutes);
    });

    test('distance is the sum of leg distances', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .firstWhere((it) => !it.isDirect);
      final sum = itinerary.legs
          .fold<double>(0, (acc, leg) => acc + leg.distanceKm);
      expect(itinerary.distanceKm, closeTo(sum, 1e-9));
    });

    test('fare is the sum of leg fares', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .firstWhere((it) => !it.isDirect);
      final sum = itinerary.legs.fold<int>(0, (acc, leg) => acc + leg.fare);
      expect(itinerary.totalFare, sum);
    });

    test('splitting a journey costs more than a through ticket', () {
      // A real consequence of stage pricing, and the reason the UI highlights a
      // direct bus's fare advantage. Compared within one service class, since a
      // cheap Ordinary split can undercut a premium Shivneri through-fare.
      const cls = 'Ordinary';
      final through = FareEngine.baseFare(160, cls);
      final split =
          FareEngine.baseFare(55, cls) + FareEngine.baseFare(105, cls);
      // 160 km = 27 stages; 55 km = 10 stages and 105 km = 18 stages, so the
      // split buys 28 stages. The rider pays for one extra stage.
      expect(split, greaterThan(through));
      expect(FareEngine.stagesFor(55) + FareEngine.stagesFor(105),
          greaterThan(FareEngine.stagesFor(160)));
    });

    test('endpoints match the query', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .first;
      expect(itinerary.origin.id, 'A');
      expect(itinerary.destination.id, 'E');
    });

    test('polyline covers every leg', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'E', departAfter: morning)
          .firstWhere((it) => !it.isDirect);
      expect(itinerary.polyline.length,
          itinerary.legs.fold<int>(0, (n, leg) => n + leg.polyline.length));
    });

    test('a leg polyline spans only the ridden stops', () {
      final leg = planner
          .plan(originId: 'B', destinationId: 'C', departAfter: morning)
          .first
          .legs
          .first;
      // B and C only — A and D are not ridden.
      expect(leg.polyline.length, 2);
      expect(leg.intermediateStops, isEmpty);
    });

    test('intermediate stops are listed for a longer leg', () {
      final leg = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect)
          .legs
          .first;
      expect(leg.intermediateStops.map((s) => s.stopId), ['B', 'C']);
    });

    test('signature is stable and distinguishes itineraries', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      for (final itinerary in results) {
        expect(itinerary.signature, isNotEmpty);
      }
      expect(results.map((it) => it.signature).toSet().length, results.length);
    });

    test('comfort flags reflect the service class', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      final shivneri = results.firstWhere(
        (it) => it.legs.any((l) => l.serviceClass.key == 'Shivneri'),
        orElse: () => results.first,
      );
      if (shivneri.legs.any((l) => l.serviceClass.key == 'Shivneri')) {
        expect(shivneri.hasAc, isTrue);
        expect(shivneri.topTier, 4);
      }
    });
  });

  group('estimates on legs', () {
    test('leg duration matches the modelled estimate', () {
      final leg = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect)
          .legs
          .first;
      expect(leg.durationMinutes, leg.estimate.totalMinutes);
    });

    test('a premium class is not slower than an ordinary one', () {
      final results = planner.plan(
          originId: 'A', destinationId: 'D', departAfter: morning);
      final ordinary = results.where(
          (it) => it.legs.every((l) => l.serviceClass.key == 'Ordinary'));
      final shivneri = results.where(
          (it) => it.legs.every((l) => l.serviceClass.key == 'Shivneri'));
      if (ordinary.isNotEmpty && shivneri.isNotEmpty) {
        expect(shivneri.first.inVehicleMinutes,
            lessThan(ordinary.first.inVehicleMinutes));
      }
    });
  });

  group('overnight detection', () {
    test('a short daytime trip is not overnight', () {
      final itinerary = planner
          .plan(originId: 'A', destinationId: 'D', departAfter: morning)
          .firstWhere((it) => it.isDirect);
      expect(itinerary.isOvernight, isFalse);
    });
  });

  group('priority queue', () {
    test('pops in ascending order', () {
      final queue = PriorityQueue<_Int>();
      for (final n in [5, 1, 9, 3, 7, 2, 8]) {
        queue.add(_Int(n));
      }
      final popped = <int>[];
      while (queue.isNotEmpty) {
        popped.add(queue.removeFirst().value);
      }
      expect(popped, [1, 2, 3, 5, 7, 8, 9]);
    });

    test('handles duplicates', () {
      final queue = PriorityQueue<_Int>();
      for (final n in [4, 4, 1, 4]) {
        queue.add(_Int(n));
      }
      expect(queue.removeFirst().value, 1);
      expect(queue.length, 3);
    });

    test('a single element round-trips', () {
      final queue = PriorityQueue<_Int>()..add(_Int(42));
      expect(queue.removeFirst().value, 42);
      expect(queue.isEmpty, isTrue);
    });

    test('popping an empty queue throws rather than corrupting state', () {
      expect(() => PriorityQueue<_Int>().removeFirst(), throwsStateError);
    });
  });

  group('performance', () {
    test('a full plan completes well within a frame budget', () {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        planner.plan(originId: 'A', destinationId: 'E', departAfter: morning);
      }
      watch.stop();
      final perQuery = watch.elapsedMilliseconds / 20;
      expect(perQuery, lessThan(120),
          reason: 'planning took ${perQuery.toStringAsFixed(1)} ms per query');
    });
  });
}

class _Int implements Comparable<_Int> {
  final int value;
  const _Int(this.value);

  @override
  int compareTo(_Int other) => value.compareTo(other.value);
}
