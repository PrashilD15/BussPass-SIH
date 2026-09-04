/// The transit network as a queryable graph, plus a time-dependent shortest-path
/// planner over it.
///
/// ## Why the previous approach could not work
///
/// The old `smartRouteSearchProvider` matched **city name strings** with a
/// hardcoded depth of two, iterated an unordered `Set` (so the same query
/// returned different answers across runs), returned the *first* transfer found
/// rather than the best, and never looked at departure times — meaning it could
/// propose a connection that departs before the first leg arrives. It also could
/// not find a route through a city that a bus merely passes through, because
/// only termini were compared.
///
/// ## What this does instead
///
/// A real graph over **stops**, where an edge exists between any two stops that
/// share a route in the correct sequence order — so Lonavala is reachable on a
/// Mumbai–Pune service even though it is neither terminus. Search is a
/// time-dependent Dijkstra: the cost of an edge is the actual *wait for the next
/// departure* plus the modelled running time, so the algorithm naturally prefers
/// a slower bus leaving now over a faster one leaving in three hours, and never
/// proposes an impossible connection.
///
/// Transfers carry an explicit penalty and a minimum connection buffer, and
/// results are diversified so the rider sees genuinely different options rather
/// than three near-identical ones.
library;

import 'dart:math' as math;

import 'package:busspass/core/math/eta_engine.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';

/// Tuning constants for the planner. Grouped so they are visible and adjustable
/// rather than scattered as magic numbers.
class PlannerConfig {
  /// Minimum minutes between arriving on one bus and boarding the next. MSRTC
  /// stands are large; a two-minute connection is not real.
  final int minTransferMinutes;

  /// Extra cost in minutes charged per transfer, on top of the actual wait.
  /// Riders will accept a longer single-bus trip to avoid changing buses with
  /// luggage, so the optimiser should too.
  final int transferPenaltyMinutes;

  /// Maximum transfers to consider.
  ///
  /// Three, not two. On the real MSRTC network a village-to-village query such
  /// as Bhandardara → Chandrapur genuinely needs three changes, and capping at
  /// two reports "no route" for a journey that exists. Each extra level costs
  /// roughly linear time because the label set is bounded by
  /// `stops × (maxTransfers + 1)`.
  final int maxTransfers;

  /// How far ahead to look for a departure before giving up on an edge.
  final int maxWaitMinutes;

  /// Walking speed for stop-to-stop transfers within a city, km/h.
  final double walkKmph;

  /// Maximum walking distance between two stops for a walk transfer, km.
  final double maxWalkKm;

  /// Number of distinct itineraries to return.
  final int resultCount;

  const PlannerConfig({
    this.minTransferMinutes = 10,
    this.transferPenaltyMinutes = 25,
    this.maxTransfers = 3,
    this.maxWaitMinutes = 14 * 60,
    this.walkKmph = 4.5,
    this.maxWalkKm = 1.5,
    this.resultCount = 4,
  });

  static const PlannerConfig standard = PlannerConfig();

  /// Fewest-changes preference: heavier transfer penalty.
  static const PlannerConfig comfort = PlannerConfig(
    transferPenaltyMinutes: 70,
    minTransferMinutes: 20,
    maxTransfers: 2,
  );

  /// Fastest-possible preference: minimal transfer aversion.
  static const PlannerConfig fastest = PlannerConfig(
    transferPenaltyMinutes: 8,
    minTransferMinutes: 10,
  );
}

/// How the rider wants results ranked.
enum JourneyPreference {
  fastest('Fastest'),
  cheapest('Cheapest'),
  fewestChanges('Fewest changes'),
  earliestArrival('Earliest arrival');

  const JourneyPreference(this.label);
  final String label;
}

/// One boarding-to-alighting movement on a single bus.
class JourneyLeg {
  final TransitRoute route;
  final TransitService service;
  final NetworkStop boardStop;
  final NetworkStop alightStop;

  /// Sequence index of the boarding stop within [route.stops].
  final int boardSeq;
  final int alightSeq;

  /// Distance travelled on this leg, kilometres.
  final double distanceKm;

  /// Departure and arrival, as absolute times.
  final DateTime departsAt;
  final DateTime arrivesAt;

  /// Modelled in-vehicle time.
  final TravelEstimate estimate;

  /// Adult fare for this leg.
  final int fare;

  /// Intermediate stops passed, excluding both endpoints.
  final List<RouteStopRef> intermediateStops;

  const JourneyLeg({
    required this.route,
    required this.service,
    required this.boardStop,
    required this.alightStop,
    required this.boardSeq,
    required this.alightSeq,
    required this.distanceKm,
    required this.departsAt,
    required this.arrivesAt,
    required this.estimate,
    required this.fare,
    required this.intermediateStops,
  });

  int get durationMinutes => arrivesAt.difference(departsAt).inMinutes;

  ServiceClass get serviceClass => service.serviceClass;

  /// Geometry of the travelled portion, for drawing the leg on a map.
  List<GeoPoint> get polyline => route.stops
      .where((s) => s.seq >= boardSeq && s.seq <= alightSeq)
      .map((s) => GeoPoint(s.lat, s.lng))
      .toList();
}

/// A wait at a transfer point between two legs.
class TransferGap {
  final NetworkStop stop;
  final DateTime arrivesAt;
  final DateTime departsAt;

  /// Walking distance between the arrival and departure stops, kilometres.
  /// Zero for a same-stand transfer.
  final double walkKm;

  const TransferGap({
    required this.stop,
    required this.arrivesAt,
    required this.departsAt,
    required this.walkKm,
  });

  int get waitMinutes => departsAt.difference(arrivesAt).inMinutes;

  /// A connection this tight is legal but risky if the first bus runs late.
  bool get isTight => waitMinutes < 20;

  /// Long enough that the rider should be told to leave the stand.
  bool get isLong => waitMinutes >= 90;
}

/// A complete origin-to-destination itinerary.
class Itinerary {
  final List<JourneyLeg> legs;
  final List<TransferGap> transfers;

  const Itinerary({required this.legs, required this.transfers});

  NetworkStop get origin => legs.first.boardStop;
  NetworkStop get destination => legs.last.alightStop;

  DateTime get departsAt => legs.first.departsAt;
  DateTime get arrivesAt => legs.last.arrivesAt;

  /// Door-to-door time including every wait.
  int get totalMinutes => arrivesAt.difference(departsAt).inMinutes;

  /// Time actually on a bus.
  int get inVehicleMinutes =>
      legs.fold(0, (sum, leg) => sum + leg.durationMinutes);

  /// Time waiting at transfer points.
  int get waitMinutes =>
      transfers.fold(0, (sum, t) => sum + t.waitMinutes);

  /// Minutes from *now* until departure, requires a reference time.
  int minutesUntilDeparture(DateTime now) =>
      departsAt.difference(now).inMinutes;

  int get transferCount => math.max(0, legs.length - 1);

  double get distanceKm =>
      legs.fold(0.0, (sum, leg) => sum + leg.distanceKm);

  /// Sum of adult leg fares. Stage pricing means this is *more* than a single
  /// through-ticket over the same distance, which is exactly why the UI shows a
  /// direct option's fare advantage.
  int get totalFare => legs.fold(0, (sum, leg) => sum + leg.fare);

  bool get isDirect => legs.length == 1;

  /// Highest service tier on the itinerary, for a comfort badge.
  int get topTier =>
      legs.map((l) => l.serviceClass.tier).reduce(math.max);

  bool get hasAc => legs.any((l) => l.serviceClass.ac);
  bool get hasSleeper => legs.any((l) => l.serviceClass.sleeper);

  /// True when the trip runs through the night, so the rider should be warned
  /// about halt stops.
  bool get isOvernight => Schedule.isOvernightJourney(
        Schedule.minuteOfDay(departsAt),
        totalMinutes,
      );

  /// Full geometry across all legs.
  List<GeoPoint> get polyline =>
      legs.expand((leg) => leg.polyline).toList();

  /// Stable identity, so the UI can keep selection across a rebuild.
  String get signature => legs
      .map((l) => '${l.route.id}|${l.service.id}|${l.boardSeq}|${l.alightSeq}'
          '|${l.departsAt.millisecondsSinceEpoch}')
      .join('>>');
}

/// Immutable transit graph with the indices the planner needs.
class TransitGraph {
  final TransitNetwork network;

  /// stop id → services that call at that stop, with the calling sequence.
  final Map<String, List<StopCall>> _callsByStop;

  /// City name (lowercased) → stop ids in that city, for walk transfers and
  /// for resolving a city-level query to concrete stands.
  final Map<String, List<String>> _stopsByCity;

  TransitGraph._(this.network, this._callsByStop, this._stopsByCity);

  /// Build the graph. O(services × stops per route).
  factory TransitGraph.build(TransitNetwork network) {
    final calls = <String, List<StopCall>>{};
    final byCity = <String, List<String>>{};

    for (final stop in network.stops) {
      final key = stop.city.toLowerCase();
      (byCity[key] ??= <String>[]).add(stop.id);
    }

    for (final service in network.services) {
      final route = network.routeById(service.routeId);
      if (route == null || route.stops.length < 2) continue;

      for (final stopRef in route.stops) {
        (calls[stopRef.stopId] ??= <StopCall>[])
            .add(StopCall(service: service, route: route, seq: stopRef.seq));
      }
    }

    return TransitGraph._(network, calls, byCity);
  }

  /// Services calling at [stopId].
  List<StopCall> callsAt(String stopId) =>
      _callsByStop[stopId] ?? const <StopCall>[];

  /// Stop ids in the same city as [stopId], excluding it.
  List<String> siblingStops(String stopId) {
    final stop = network.stopById(stopId);
    if (stop == null) return const [];
    final ids = _stopsByCity[stop.city.toLowerCase()] ?? const <String>[];
    return ids.where((id) => id != stopId).toList();
  }

  /// Every stop reachable from [stopId] on a single bus, no transfers.
  Set<String> directlyReachable(String stopId) {
    final out = <String>{};
    for (final call in callsAt(stopId)) {
      for (final stopRef in call.route.stops) {
        if (stopRef.seq != call.seq) out.add(stopRef.stopId);
      }
    }
    out.remove(stopId);
    return out;
  }

  /// Number of distinct services calling at [stopId] — a usable proxy for how
  /// important a stand is, used to size map markers and rank search results.
  int serviceCountAt(String stopId) => callsAt(stopId).length;

  /// Stops within [radiusKm] of a point, nearest first.
  List<({NetworkStop stop, double distanceKm})> stopsNear(
    GeoPoint point, {
    double radiusKm = 25,
    int limit = 12,
  }) {
    final out = <({NetworkStop stop, double distanceKm})>[];
    for (final stop in network.stops) {
      final d = Geo.distanceKm(point, GeoPoint(stop.lat, stop.lng));
      if (d <= radiusKm) out.add((stop: stop, distanceKm: d));
    }
    out.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return out.take(limit).toList();
  }

  /// Nearest stop to a point regardless of distance, with the distance so the
  /// caller can reject an implausible match instead of silently snapping a user
  /// in Delhi to a Maharashtra stand.
  ({NetworkStop stop, double distanceKm})? nearestStop(GeoPoint point) {
    NetworkStop? best;
    var bestKm = double.infinity;
    for (final stop in network.stops) {
      final d = Geo.distanceKm(point, GeoPoint(stop.lat, stop.lng));
      if (d < bestKm) {
        bestKm = d;
        best = stop;
      }
    }
    if (best == null) return null;
    return (stop: best, distanceKm: bestKm);
  }
}

/// A service calling at a stop at a given sequence position.
///
/// Public because callers legitimately need to ask "which services stop here,
/// and where in their run" — the map, the stop detail sheet, and the departure
/// board all do.
class StopCall {
  final TransitService service;
  final TransitRoute route;
  final int seq;

  const StopCall({
    required this.service,
    required this.route,
    required this.seq,
  });
}

/// Dijkstra label: the best known arrival at a stop under a transfer count.
class _Label implements Comparable<_Label> {
  final String stopId;

  /// Earliest known arrival.
  final DateTime arrival;

  /// Cost in minutes: elapsed time plus transfer penalties. This is what the
  /// priority queue orders by, and it is why the planner can prefer a direct
  /// bus that arrives slightly later.
  final int cost;

  final int transfers;

  /// Backpointer for path reconstruction.
  final _Label? previous;

  /// The leg that produced this label, `null` for the source.
  final JourneyLeg? viaLeg;

  /// Walk distance taken to reach this stop, if this label came from a walk.
  final double walkKm;

  const _Label({
    required this.stopId,
    required this.arrival,
    required this.cost,
    required this.transfers,
    this.previous,
    this.viaLeg,
    this.walkKm = 0,
  });

  @override
  int compareTo(_Label other) {
    final byCost = cost.compareTo(other.cost);
    if (byCost != 0) return byCost;
    return arrival.compareTo(other.arrival);
  }
}

class JourneyPlanner {
  final TransitGraph graph;
  final PlannerConfig config;

  const JourneyPlanner(this.graph, {this.config = PlannerConfig.standard});

  /// Plan itineraries from [originId] to [destinationId] departing at or after
  /// [departAfter].
  ///
  /// Returns up to `config.resultCount` **distinct** itineraries, ranked by
  /// [preference]. An empty list means genuinely no path exists within the
  /// transfer and wait limits.
  List<Itinerary> plan({
    required String originId,
    required String destinationId,
    required DateTime departAfter,
    JourneyPreference preference = JourneyPreference.fastest,
  }) {
    if (originId == destinationId) return const [];
    if (graph.network.stopById(originId) == null) return const [];
    if (graph.network.stopById(destinationId) == null) return const [];

    // Collect candidates from several search passes rather than a single
    // shortest path, so the rider gets real alternatives. Each pass constrains
    // the search differently, which surfaces itineraries a single optimum hides.
    final candidates = <String, Itinerary>{};

    void collect(Iterable<Itinerary> found) {
      for (final it in found) {
        candidates.putIfAbsent(it.signature, () => it);
      }
    }

    // Pass 1 — all direct services, enumerated exhaustively. Direct buses are
    // what riders want most, and there are few enough to list them all.
    collect(_directItineraries(
      originId: originId,
      destinationId: destinationId,
      departAfter: departAfter,
    ));

    // Pass 2 — time-dependent Dijkstra under the standard config.
    collect(_search(
      originId: originId,
      destinationId: destinationId,
      departAfter: departAfter,
      config: config,
    ));

    // Passes 3 and 4 explore different transfer trade-offs. They are skipped
    // when pass 2 already produced enough genuinely distinct options, because
    // each is a full graph search and most queries do not need them.
    final needsMore = candidates.length < config.resultCount * 2;

    if (needsMore) {
      // A transfer-averse pass, to surface the fewest-changes option even when
      // it is not time-optimal.
      collect(_search(
        originId: originId,
        destinationId: destinationId,
        departAfter: departAfter,
        config: PlannerConfig.comfort,
      ));

      // A transfer-tolerant pass, for when changing buses genuinely saves hours.
      collect(_search(
        originId: originId,
        destinationId: destinationId,
        departAfter: departAfter,
        config: PlannerConfig.fastest,
      ));
    }

    final ranked = candidates.values.toList();
    _rank(ranked, preference, departAfter);
    return _diversify(ranked, preference);
  }

  /// Every single-bus option between two stops, with each service's next few
  /// departures.
  List<Itinerary> _directItineraries({
    required String originId,
    required String destinationId,
    required DateTime departAfter,
    int departuresPerService = 3,
  }) {
    final out = <Itinerary>[];

    for (final call in graph.callsAt(originId)) {
      final route = call.route;
      final alightRef = route.stopRefById(destinationId);
      if (alightRef == null) continue;

      // A service only carries the rider in its own direction of travel.
      if (!_servesDirection(call.service, route, call.seq, alightRef.seq)) {
        continue;
      }

      final departures = _nextDepartures(
        service: call.service,
        route: route,
        boardSeq: call.seq,
        after: departAfter,
        count: departuresPerService,
      );

      for (final departure in departures) {
        final leg = _buildLeg(
          route: route,
          service: call.service,
          boardSeq: call.seq,
          alightSeq: alightRef.seq,
          departsAt: departure,
        );
        if (leg != null) out.add(Itinerary(legs: [leg], transfers: const []));
      }
    }
    return out;
  }

  /// Time-dependent Dijkstra over stops.
  List<Itinerary> _search({
    required String originId,
    required String destinationId,
    required DateTime departAfter,
    required PlannerConfig config,
  }) {
    // Best cost seen per (stop, transfers) so a cheaper path with more
    // transfers is not discarded by a pricier path with fewer.
    final best = <String, int>{};
    final queue = PriorityQueue<_Label>();
    final results = <Itinerary>[];

    queue.add(_Label(
      stopId: originId,
      arrival: departAfter,
      cost: 0,
      transfers: 0,
    ));

    // Also seed sibling stands in the origin city — a rider at Swargate can
    // walk to Shivajinagar if that is where the bus actually leaves from.
    for (final siblingId in graph.siblingStops(originId)) {
      final walk = _walkBetween(originId, siblingId);
      if (walk == null) continue;
      queue.add(_Label(
        stopId: siblingId,
        arrival: departAfter.add(Duration(minutes: walk.minutes)),
        cost: walk.minutes,
        transfers: 0,
        walkKm: walk.km,
      ));
    }

    var expansions = 0;
    const expansionCap = 40000; // hard bound; the graph is ~90 stops

    while (queue.isNotEmpty && expansions < expansionCap) {
      final label = queue.removeFirst();
      expansions++;

      final key = '${label.stopId}|${label.transfers}';
      final known = best[key];
      if (known != null && known <= label.cost) continue;
      best[key] = label.cost;

      if (label.stopId == destinationId && label.viaLeg != null) {
        final itinerary = _reconstruct(label);
        if (itinerary != null) results.add(itinerary);
        // Keep searching: a later label may yield a better-ranked alternative
        // with a different transfer count.
        if (results.length >= config.resultCount * 3) break;
        continue;
      }

      if (label.transfers > config.maxTransfers) continue;

      // The earliest this rider can board here.
      final readyAt = label.viaLeg == null
          ? label.arrival
          : label.arrival.add(Duration(minutes: config.minTransferMinutes));

      for (final call in graph.callsAt(label.stopId)) {
        final route = call.route;

        final departure = _nextDeparture(
          service: call.service,
          route: route,
          boardSeq: call.seq,
          after: readyAt,
          maxWaitMinutes: config.maxWaitMinutes,
        );
        if (departure == null) continue;

        final transfers = label.viaLeg == null ? 0 : label.transfers + 1;
        if (transfers > config.maxTransfers) continue;

        // Precomputed per-service running-time offsets make the arrival time at
        // any downstream stop an O(1) subtraction. Building a full JourneyLeg
        // per candidate edge — with its own ETA model run and stop-list
        // allocation — dominated the profile, so legs are only materialised for
        // edges that survive pruning.
        final offsets = _boardOffsets(call.service, route);
        final boardOffset = offsets[call.seq] ?? 0;

        for (final stopRef in route.stops) {
          if (stopRef.stopId == label.stopId) continue;
          if (!_servesDirection(call.service, route, call.seq, stopRef.seq)) {
            continue;
          }

          // A bidirectional corridor service is rideable either way, so the
          // offset difference is taken as a magnitude. Only a *directional*
          // service has a signed running order, and `_servesDirection` has
          // already rejected the wrong way round for those.
          final rideMinutes =
              ((offsets[stopRef.seq] ?? 0) - boardOffset).abs();
          if (rideMinutes <= 0) continue;

          final arrival = departure.add(Duration(minutes: rideMinutes));
          final elapsed = arrival.difference(departAfter).inMinutes;
          final cost = elapsed + transfers * config.transferPenaltyMinutes;

          final nextKey = '${stopRef.stopId}|$transfers';
          final seen = best[nextKey];
          if (seen != null && seen <= cost) continue;

          // Only now is the edge worth the cost of full materialisation.
          if (_pathContains(label, stopRef.stopId)) continue;

          final leg = _buildLeg(
            route: route,
            service: call.service,
            boardSeq: call.seq,
            alightSeq: stopRef.seq,
            departsAt: departure,
          );
          if (leg == null) continue;

          queue.add(_Label(
            stopId: stopRef.stopId,
            arrival: leg.arrivesAt,
            cost: cost,
            transfers: transfers,
            previous: label,
            viaLeg: leg,
          ));
        }
      }

      // Walk to another stand in the same city, so a transfer can move between
      // stands rather than requiring both legs to use one.
      if (label.transfers < config.maxTransfers) {
        for (final siblingId in graph.siblingStops(label.stopId)) {
          if (_pathContains(label, siblingId)) continue;
          final walk = _walkBetween(label.stopId, siblingId);
          if (walk == null || walk.km > config.maxWalkKm) continue;

          final cost = label.cost + walk.minutes;
          final nextKey = '$siblingId|${label.transfers}';
          final seen = best[nextKey];
          if (seen != null && seen <= cost) continue;

          queue.add(_Label(
            stopId: siblingId,
            arrival: label.arrival.add(Duration(minutes: walk.minutes)),
            cost: cost,
            transfers: label.transfers,
            previous: label,
            viaLeg: label.viaLeg,
            walkKm: walk.km,
          ));
        }
      }
    }

    return results;
  }

  /// Walk to a physically-different stand in the same city.
  ({double km, int minutes})? _walkBetween(String fromId, String toId) {
    final a = graph.network.stopById(fromId);
    final b = graph.network.stopById(toId);
    if (a == null || b == null) return null;
    final km = Geo.distanceKm(GeoPoint(a.lat, a.lng), GeoPoint(b.lat, b.lng));
    if (km > config.maxWalkKm) return null;
    // Street distance exceeds straight-line; 1.35 is a standard detour factor.
    final minutes = math.max(3, (km * 1.35 / config.walkKmph * 60).round());
    return (km: km, minutes: minutes);
  }

  /// Whether [label]'s path already visits [stopId], preventing cycles.
  bool _pathContains(_Label label, String stopId) {
    _Label? cursor = label;
    while (cursor != null) {
      if (cursor.stopId == stopId) return true;
      cursor = cursor.previous;
    }
    return false;
  }

  /// Whether a service carries riders from [boardSeq] to [alightSeq].
  ///
  /// Corridor services are modelled as running both ways. A directional service
  /// — a scraped depot board, or its modelled return working — runs one way
  /// only, so a Sangamner→Pune board cannot be ridden Pune→Sangamner. The
  /// return working is what makes Sangamner reachable.
  bool _servesDirection(
    TransitService service,
    TransitRoute route,
    int boardSeq,
    int alightSeq,
  ) {
    if (boardSeq == alightSeq) return false;
    if (!service.isDirectional) return true;

    final originSeq = _serviceOriginSeq(service, route);
    if (originSeq == null) return true;

    // Sequence numbers ascend from the route origin, so a service starting at
    // the first stop travels in ascending order and one starting at the last
    // stop travels in descending order.
    final ascending = originSeq == 1;
    return ascending ? alightSeq > boardSeq : alightSeq < boardSeq;
  }

  /// Sequence position the service begins its run at.
  int? _serviceOriginSeq(TransitService service, TransitRoute route) {
    final fromStopId = service.fromStopId;
    if (fromStopId == null) return null;
    return route.stopRefById(fromStopId)?.seq;
  }

  /// Absolute time of the next departure from [boardSeq] at or after [after].
  ///
  /// Board times are offset from the service's origin departure by the modelled
  /// running time to the boarding stop, so a mid-route stop shows when the bus
  /// reaches *it*, not when it left the terminus.
  DateTime? _nextDeparture({
    required TransitService service,
    required TransitRoute route,
    required int boardSeq,
    required DateTime after,
    required int maxWaitMinutes,
  }) {
    final offsets = _boardOffsets(service, route);
    final offset = offsets[boardSeq] ?? 0;

    Departure? best;
    for (final scheduled in service.departures) {
      final boardMinute = Schedule.addMinutes(scheduled, offset);
      final resolved = Schedule.resolve(boardMinute, after);
      if (resolved.minutesUntil > maxWaitMinutes) continue;
      if (best == null || resolved.minutesUntil < best.minutesUntil) {
        best = resolved;
      }
    }
    return best?.at;
  }

  /// The next [count] departures from a boarding stop.
  List<DateTime> _nextDepartures({
    required TransitService service,
    required TransitRoute route,
    required int boardSeq,
    required DateTime after,
    required int count,
  }) {
    final offsets = _boardOffsets(service, route);
    final offset = offsets[boardSeq] ?? 0;

    final resolved = service.departures
        .map((m) => Schedule.resolve(Schedule.addMinutes(m, offset), after))
        .toList()
      ..sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));

    return resolved.take(count).map((d) => d.at).toList();
  }

  /// Cached running-time offsets from the service origin to each stop sequence.
  ///
  /// Keyed by service id, which is unique across the network. Recomputing these
  /// per edge evaluation dominated the search profile.
  static final Map<String, Map<int, int>> _offsetCache = {};

  /// Clear the offset cache. Only needed when the network is swapped at runtime,
  /// e.g. after a Firestore overlay arrives.
  static void invalidateCaches() => _offsetCache.clear();

  Map<int, int> _boardOffsets(TransitService service, TransitRoute route) {
    final cached = _offsetCache[service.id];
    if (cached != null) return cached;

    final forward = EtaEngine.stopArrivalOffsets(
      cumulativeKm: route.cumulativeKm,
      serviceClass: service.serviceClass,
      departureMinuteOfDay:
          service.departures.isEmpty ? 9 * 60 : service.departures.first,
    );

    // A service running against the stored sequence measures its offsets from
    // the other end: its first stop is the route's last.
    final originSeq = _serviceOriginSeq(service, route);
    final descending = originSeq != null && originSeq != 1;

    final out = <int, int>{};
    for (var i = 0; i < route.stops.length; i++) {
      final seq = route.stops[i].seq;
      out[seq] = descending ? forward.last - forward[i] : forward[i];
    }

    _offsetCache[service.id] = out;
    return out;
  }

  /// Materialise a leg, computing distance, duration, and fare.
  JourneyLeg? _buildLeg({
    required TransitRoute route,
    required TransitService service,
    required int boardSeq,
    required int alightSeq,
    required DateTime departsAt,
  }) {
    final boardRef = route.stopRefBySeq(boardSeq);
    final alightRef = route.stopRefBySeq(alightSeq);
    if (boardRef == null || alightRef == null) return null;

    final boardStop = graph.network.stopById(boardRef.stopId);
    final alightStop = graph.network.stopById(alightRef.stopId);
    if (boardStop == null || alightStop == null) return null;

    final distanceKm = (alightRef.cumKm - boardRef.cumKm).abs();
    if (distanceKm <= 0) return null;

    final lo = math.min(boardSeq, alightSeq);
    final hi = math.max(boardSeq, alightSeq);
    final intermediate = route.stops
        .where((s) => s.seq > lo && s.seq < hi)
        .toList();

    final estimate = EtaEngine.estimate(
      distanceKm: distanceKm,
      serviceClass: service.serviceClass,
      intermediateStops: intermediate.length,
      departureMinuteOfDay: Schedule.minuteOfDay(departsAt),
      traffic: EtaEngine.inferTraffic(Schedule.minuteOfDay(departsAt)),
    );

    return JourneyLeg(
      route: route,
      service: service,
      boardStop: boardStop,
      alightStop: alightStop,
      boardSeq: boardSeq,
      alightSeq: alightSeq,
      distanceKm: distanceKm,
      departsAt: departsAt,
      arrivesAt: departsAt.add(Duration(minutes: estimate.totalMinutes)),
      estimate: estimate,
      fare: FareEngine.baseFare(distanceKm, service.serviceClass.key),
      intermediateStops: intermediate,
    );
  }

  /// Walk the backpointer chain into an [Itinerary].
  Itinerary? _reconstruct(_Label end) {
    final legs = <JourneyLeg>[];
    final walkAt = <String, double>{};

    _Label? cursor = end;
    JourneyLeg? lastSeen;
    while (cursor != null) {
      final leg = cursor.viaLeg;
      if (leg != null && leg != lastSeen) {
        legs.insert(0, leg);
        lastSeen = leg;
      }
      if (cursor.walkKm > 0) walkAt[cursor.stopId] = cursor.walkKm;
      cursor = cursor.previous;
    }

    if (legs.isEmpty) return null;

    final transfers = <TransferGap>[];
    for (var i = 0; i < legs.length - 1; i++) {
      final arrive = legs[i];
      final depart = legs[i + 1];
      transfers.add(TransferGap(
        stop: depart.boardStop,
        arrivesAt: arrive.arrivesAt,
        departsAt: depart.departsAt,
        walkKm: walkAt[depart.boardStop.id] ?? 0,
      ));
    }

    // Reject anything that violates causality. Defensive: the search should
    // never produce this, but a silent bad itinerary is far worse than a
    // dropped one.
    for (final gap in transfers) {
      if (gap.departsAt.isBefore(gap.arrivesAt)) return null;
    }

    return Itinerary(legs: legs, transfers: transfers);
  }

  /// Order candidates by the rider's stated preference.
  void _rank(
    List<Itinerary> items,
    JourneyPreference preference,
    DateTime now,
  ) {
    switch (preference) {
      case JourneyPreference.fastest:
        // Total elapsed from *now*, so a bus leaving sooner wins even if its
        // in-vehicle time is longer.
        items.sort((a, b) {
          final aEnd = a.arrivesAt.difference(now).inMinutes;
          final bEnd = b.arrivesAt.difference(now).inMinutes;
          final byEnd = aEnd.compareTo(bEnd);
          if (byEnd != 0) return byEnd;
          return a.transferCount.compareTo(b.transferCount);
        });
      case JourneyPreference.cheapest:
        items.sort((a, b) {
          final byFare = a.totalFare.compareTo(b.totalFare);
          if (byFare != 0) return byFare;
          return a.arrivesAt.compareTo(b.arrivesAt);
        });
      case JourneyPreference.fewestChanges:
        items.sort((a, b) {
          final byTransfers = a.transferCount.compareTo(b.transferCount);
          if (byTransfers != 0) return byTransfers;
          return a.arrivesAt.compareTo(b.arrivesAt);
        });
      case JourneyPreference.earliestArrival:
        items.sort((a, b) => a.arrivesAt.compareTo(b.arrivesAt));
    }
  }

  /// Trim to distinct options.
  ///
  /// Two itineraries on the same route and service class arriving within 45
  /// minutes of each other are the same answer to the rider, so only the better
  /// one is kept. Beyond that, the top-ranked option for each transfer count is
  /// force-included, guaranteeing that a direct bus is always offered when one
  /// exists.
  List<Itinerary> _diversify(
    List<Itinerary> ranked,
    JourneyPreference preference,
  ) {
    final out = <Itinerary>[];
    final seenShape = <String>{};

    String shapeOf(Itinerary it) => it.legs
        .map((l) => '${l.route.id}:${l.serviceClass.key}')
        .join('>');

    for (final it in ranked) {
      final shape = shapeOf(it);
      final tooSimilar = out.any((existing) =>
          shapeOf(existing) == shape &&
          existing.arrivesAt.difference(it.arrivesAt).inMinutes.abs() < 45);
      if (tooSimilar) continue;

      out.add(it);
      seenShape.add(shape);
      if (out.length >= config.resultCount) break;
    }

    // Guarantee a direct option is present when one exists at all.
    if (!out.any((it) => it.isDirect)) {
      final direct = ranked.firstWhere(
        (it) => it.isDirect,
        orElse: () => ranked.isEmpty
            ? const Itinerary(legs: [], transfers: [])
            : ranked.first,
      );
      if (direct.legs.isNotEmpty && !out.contains(direct)) {
        if (out.length >= config.resultCount) out.removeLast();
        out.insert(0, direct);
      }
    }

    // Guarantee the cheapest option is visible even when ranking by speed.
    if (preference != JourneyPreference.cheapest && ranked.length > out.length) {
      final cheapest = ranked.reduce(
          (a, b) => a.totalFare <= b.totalFare ? a : b);
      if (!out.contains(cheapest)) {
        if (out.length >= config.resultCount) out.removeLast();
        out.add(cheapest);
      }
    }

    return out;
  }
}

/// A binary min-heap.
///
/// `dart:collection` has no priority queue, and the `collection` package's
/// `HeapPriorityQueue` would work, but a 60-line local implementation keeps the
/// planner's complexity guarantees explicit and dependency-free.
class PriorityQueue<T extends Comparable<T>> {
  final List<T> _heap = [];

  bool get isEmpty => _heap.isEmpty;
  bool get isNotEmpty => _heap.isNotEmpty;
  int get length => _heap.length;

  void add(T value) {
    _heap.add(value);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_heap[i].compareTo(_heap[parent]) >= 0) break;
      final tmp = _heap[i];
      _heap[i] = _heap[parent];
      _heap[parent] = tmp;
      i = parent;
    }
  }

  T removeFirst() {
    if (_heap.isEmpty) {
      throw StateError('removeFirst() on an empty PriorityQueue');
    }
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isEmpty) return first;

    _heap[0] = last;
    var i = 0;
    while (true) {
      final left = 2 * i + 1;
      final right = left + 1;
      var smallest = i;
      if (left < _heap.length &&
          _heap[left].compareTo(_heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < _heap.length &&
          _heap[right].compareTo(_heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == i) break;
      final tmp = _heap[i];
      _heap[i] = _heap[smallest];
      _heap[smallest] = tmp;
      i = smallest;
    }
    return first;
  }
}
