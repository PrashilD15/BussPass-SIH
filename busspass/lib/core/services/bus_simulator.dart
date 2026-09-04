/// Deterministic bus fleet simulator.
///
/// Every bus is advanced along its **real route polyline** on its **real
/// timetable**, using the same [EtaEngine] speed model the planner uses for
/// predictions. That consistency is the point: a simulated bus arrives when the
/// app predicted it would, so live tracking, progress bars, ETA, delay reporting,
/// and transit detection are all genuinely exercised rather than faked.
///
/// The word "simulated" is used honestly. Every [LiveBus] this produces carries
/// `isSimulated: true`, and the UI labels it. The old code hardcoded a
/// coordinate, a `0.35` progress value, and the string `'ETA: 11:10 AM'`, then
/// pulsed a "Live Sync" badge over them.
///
/// ## Determinism
///
/// Position is a pure function of `(service, departure, wall clock)`. There is no
/// accumulated state and no random walk, so:
///  - the same moment always yields the same fleet,
///  - a rebuild does not teleport a bus,
///  - and a test can assert an exact position.
///
/// Per-bus variation — one bus running eight minutes late, another early — comes
/// from a hash of the bus id, so it is stable across restarts while still looking
/// like a real fleet rather than a metronome.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:busspass/core/math/eta_engine.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';

class BusSimulator {
  final TransitNetwork network;

  /// How often the fleet is recomputed.
  final Duration tick;

  /// Maximum number of buses to simulate.
  ///
  /// Bounded because every tick recomputes each bus's polyline position. On the
  /// bundled network an unbounded fleet would be thousands of buses, none of
  /// which a rider can see.
  final int fleetCap;

  BusSimulator({
    required this.network,
    this.tick = const Duration(seconds: 3),
    this.fleetCap = 220,
  });

  /// Rest halt duration, matching [EtaEngine.breakDurationMinutes].
  static const int _breakMinutes = EtaEngine.breakDurationMinutes;

  /// How long a bus waits at an intermediate stop.
  static const int _dwellSeconds = 70;

  /// Grace period after arrival during which the bus stays visible at its
  /// terminus, so a rider watching an arrival sees it complete.
  static const Duration _arrivedLinger = Duration(minutes: 4);

  /// The fleet at [now].
  ///
  /// A run is included when `now` falls between its departure and its arrival
  /// plus the linger window.
  List<LiveBus> fleetAt(DateTime now) {
    final buses = <LiveBus>[];

    for (final service in network.services) {
      final route = network.routeById(service.routeId);
      if (route == null || route.stops.length < 2) continue;

      final offsets = _offsetsFor(service, route);
      final runMinutes = offsets.isEmpty ? 0 : offsets.last;
      if (runMinutes <= 0) continue;

      for (final departureMinute in service.departures) {
        final departure = _resolveDeparture(departureMinute, now, runMinutes);
        if (departure == null) continue;

        final bus = _busFor(
          service: service,
          route: route,
          offsets: offsets,
          departure: departure,
          runMinutes: runMinutes,
          now: now,
        );
        if (bus != null) buses.add(bus);

        if (buses.length >= fleetCap) return buses;
      }
    }

    return buses;
  }

  /// Buses currently running on a given route.
  List<LiveBus> busesOnRoute(String routeId, DateTime now) =>
      fleetAt(now).where((b) => b.routeId == routeId).toList();

  /// The bus nearest a point, within [radiusKm].
  LiveBus? nearestBus(GeoPoint point, DateTime now, {double radiusKm = 5}) {
    LiveBus? best;
    var bestKm = radiusKm;
    for (final bus in fleetAt(now)) {
      final km = Geo.distanceKm(point, bus.point);
      if (km < bestKm) {
        bestKm = km;
        best = bus;
      }
    }
    return best;
  }

  /// A stream that re-emits the fleet every [tick].
  ///
  /// Emits immediately so a subscriber never renders an empty map while waiting
  /// for the first interval.
  Stream<List<LiveBus>> watchFleet() async* {
    yield fleetAt(DateTime.now());
    yield* Stream.periodic(tick, (_) => fleetAt(DateTime.now()));
  }

  /// A stream for one specific bus, ending when its run completes.
  Stream<LiveBus?> watchBus(String busId) async* {
    LiveBus? find(DateTime at) {
      for (final bus in fleetAt(at)) {
        if (bus.id == busId) return bus;
      }
      return null;
    }

    yield find(DateTime.now());
    yield* Stream.periodic(tick, (_) => find(DateTime.now()));
  }

  /// Resolve a minute-of-day departure to the concrete run that is in progress
  /// at [now], if any.
  ///
  /// Today's and yesterday's departures are both considered, because an
  /// overnight run that left at 21:00 is still on the road at 04:00 the next
  /// morning — a subtlety that minute-of-day arithmetic alone would drop.
  DateTime? _resolveDeparture(int departureMinute, DateTime now, int runMinutes) {
    final today = DateTime(now.year, now.month, now.day)
        .add(Duration(minutes: Schedule.wrap(departureMinute)));

    for (final candidate in [
      today.subtract(const Duration(days: 1)),
      today,
    ]) {
      final end = candidate
          .add(Duration(minutes: runMinutes))
          .add(_arrivedLinger);
      if (!now.isBefore(candidate) && now.isBefore(end)) return candidate;
    }
    return null;
  }

  /// Build the bus for one in-progress run.
  LiveBus? _busFor({
    required TransitService service,
    required TransitRoute route,
    required List<int> offsets,
    required DateTime departure,
    required int runMinutes,
    required DateTime now,
  }) {
    final busId = _plateFor(service, departure);

    // A stable per-run delay so the fleet looks real. Buses run late far more
    // often than early, so the distribution is deliberately skewed: -3 to +14
    // minutes.
    final delayMinutes = _stableDelay(busId);

    final elapsed = now.difference(departure).inSeconds / 60.0 - delayMinutes;

    if (elapsed < 0) {
      // Departure time has passed but this bus is running late, so it is still
      // sitting at its origin.
      final first = route.stops.first;
      return LiveBus(
        id: busId,
        routeId: route.id,
        serviceId: service.id,
        busType: service.busType,
        lat: first.lat,
        lng: first.lng,
        speedKmph: 0,
        heading: Geo.bearing(first.point, route.stops[1].point),
        travelledKm: 0,
        nextStopSeq: first.seq,
        state: BusState.atOrigin,
        updatedAt: now,
        scheduledDeparture: departure,
        passengerCount: _passengerCountFor(busId, service, 0),
        isSimulated: true,
      );
    }

    if (elapsed >= runMinutes) {
      final last = route.stops.last;
      return LiveBus(
        id: busId,
        routeId: route.id,
        serviceId: service.id,
        busType: service.busType,
        lat: last.lat,
        lng: last.lng,
        speedKmph: 0,
        heading: Geo.bearing(
            route.stops[route.stops.length - 2].point, last.point),
        travelledKm: route.distanceKm,
        nextStopSeq: last.seq,
        state: BusState.arrived,
        updatedAt: now,
        scheduledDeparture: departure,
        passengerCount: _passengerCountFor(busId, service, 1),
        isSimulated: true,
      );
    }

    // Direction: a directional service starting at the far terminus runs the
    // stop sequence backwards.
    final reversed = _runsReversed(service, route);

    // Distances are measured from the *service's* origin, which for a reversed
    // working is the far end of the stored sequence.
    final cumulative = reversed
        ? route.cumulativeKm
            .map((km) => route.distanceKm - km)
            .toList()
            .reversed
            .toList()
        : route.cumulativeKm;

    final position = _positionAt(
      elapsedMinutes: elapsed,
      offsets: offsets,
      cumulative: cumulative,
      route: route,
      reversed: reversed,
      runMinutes: runMinutes,
    );

    final stops = reversed ? route.stops.reversed.toList() : route.stops;
    final nextIndex = math.min(position.legIndex + 1, stops.length - 1);

    return LiveBus(
      id: busId,
      routeId: route.id,
      serviceId: service.id,
      busType: service.busType,
      lat: position.point.lat,
      lng: position.point.lng,
      speedKmph: position.speedKmph,
      heading: position.heading,
      travelledKm: position.travelledKm,
      nextStopSeq: stops[nextIndex].seq,
      state: position.state,
      updatedAt: now,
      scheduledDeparture: departure,
      passengerCount:
          _passengerCountFor(busId, service, position.travelledKm / math.max(1, route.distanceKm)),
      isSimulated: true,
    );
  }

  /// Interpolate a bus's position from elapsed running time.
  ///
  /// Walks the per-stop time offsets to find the current leg, then interpolates
  /// within it. Dwell time at each stop and rest halts on long runs are modelled
  /// explicitly, so a bus genuinely pauses at stops instead of gliding through
  /// them at constant speed.
  _SimPosition _positionAt({
    required double elapsedMinutes,
    required List<int> offsets,
    required List<double> cumulative,
    required TransitRoute route,
    required bool reversed,
    required int runMinutes,
  }) {
    // Rest halt: on a long run the bus stops for a fixed period.
    final breakCount = runMinutes ~/ EtaEngine.breakIntervalMinutes;
    for (var i = 1; i <= breakCount; i++) {
      final breakStart = i * EtaEngine.breakIntervalMinutes.toDouble();
      final breakEnd = breakStart + _breakMinutes;
      if (elapsedMinutes >= breakStart && elapsedMinutes < breakEnd) {
        final frozen =
            _interpolate(breakStart, offsets, cumulative, route, reversed);
        return _SimPosition(
          point: frozen.point,
          travelledKm: frozen.travelledKm,
          heading: frozen.heading,
          speedKmph: 0,
          legIndex: frozen.legIndex,
          state: BusState.onBreak,
        );
      }
    }

    final resolved =
        _interpolate(elapsedMinutes, offsets, cumulative, route, reversed);

    // Dwell: within the dwell window after reaching a stop, the bus is halted.
    final legOffset = offsets[resolved.legIndex].toDouble();
    final sinceStopSeconds = (elapsedMinutes - legOffset) * 60;
    final atStop = resolved.legIndex > 0 &&
        resolved.legIndex < offsets.length - 1 &&
        sinceStopSeconds >= 0 &&
        sinceStopSeconds < _dwellSeconds;

    if (atStop) {
      return _SimPosition(
        point: resolved.point,
        travelledKm: resolved.travelledKm,
        heading: resolved.heading,
        speedKmph: 0,
        legIndex: resolved.legIndex,
        state: BusState.atStop,
      );
    }

    return resolved;
  }

  /// Interpolate along the corridor for a given elapsed time.
  _SimPosition _interpolate(
    double elapsedMinutes,
    List<int> offsets,
    List<double> cumulative,
    TransitRoute route,
    bool reversed,
  ) {
    // Find the leg containing this moment.
    var leg = 0;
    for (var i = 0; i < offsets.length - 1; i++) {
      if (elapsedMinutes >= offsets[i]) leg = i;
    }

    final legStart = offsets[leg].toDouble();
    final legEnd = offsets[math.min(leg + 1, offsets.length - 1)].toDouble();
    final legSpan = legEnd - legStart;

    final t = legSpan <= 0
        ? 0.0
        : ((elapsedMinutes - legStart) / legSpan).clamp(0.0, 1.0);

    final kmStart = cumulative[leg];
    final kmEnd = cumulative[math.min(leg + 1, cumulative.length - 1)];
    final travelledKm = kmStart + (kmEnd - kmStart) * t;

    // `travelledKm` is a road distance measured from the *service's* origin.
    // The corridor's own mapping converts that to a coordinate, honouring the
    // per-segment road-vs-straight-line scaling. A reversed working measures
    // from the other end, so the value is mirrored before conversion.
    final routeKm = reversed ? route.distanceKm - travelledKm : travelledKm;
    final point = route.pointAtRoadKm(routeKm);
    final forwardHeading = route.bearingAtRoadKm(routeKm);
    final heading = reversed ? (forwardHeading + 180) % 360 : forwardHeading;

    // Instantaneous speed for this leg.
    final legKm = (kmEnd - kmStart).abs();
    final speed = legSpan <= 0 ? 0.0 : legKm / (legSpan / 60.0);

    return _SimPosition(
      point: point,
      travelledKm: travelledKm,
      heading: heading,
      speedKmph: speed,
      legIndex: leg,
      state: BusState.inTransit,
    );
  }

  /// Per-stop running-time offsets, cached per service.
  static final Map<String, List<int>> _offsetCache = {};

  List<int> _offsetsFor(TransitService service, TransitRoute route) {
    final cached = _offsetCache[service.id];
    if (cached != null) return cached;

    final offsets = EtaEngine.stopArrivalOffsets(
      cumulativeKm: route.cumulativeKm,
      serviceClass: service.serviceClass,
      departureMinuteOfDay:
          service.departures.isEmpty ? 9 * 60 : service.departures.first,
    );
    _offsetCache[service.id] = offsets;
    return offsets;
  }

  /// Clear caches. Needed when the network is swapped at runtime.
  static void invalidateCaches() => _offsetCache.clear();

  bool _runsReversed(TransitService service, TransitRoute route) {
    final from = service.fromStopId;
    if (from == null) return false;
    final ref = route.stopRefById(from);
    return ref != null && ref.seq != 1;
  }

  /// A stable registration plate for a run.
  ///
  /// Real MSRTC plates are `MH{district:2}{series:2}{number:4}`. Deriving it from
  /// the service and departure means the same run always shows the same bus,
  /// which matters when a rider is tracking one.
  String _plateFor(TransitService service, DateTime departure) {
    final seed = _hash('${service.id}|${departure.millisecondsSinceEpoch}');
    const districts = ['12', '14', '20', '31', '40', '43', '04', '15'];
    const series = ['AB', 'BH', 'CD', 'EN', 'JK', 'LM', 'PQ', 'ST'];
    final district = districts[seed % districts.length];
    final letters = series[(seed >> 4) % series.length];
    final number = 1000 + (seed >> 8) % 9000;
    return 'MH$district$letters$number';
  }

  /// A stable delay for a bus, in minutes.
  ///
  /// Skewed late: -3 to +14. Real intercity buses lose time far more often than
  /// they gain it, and an ETA model that only ever predicts on-time arrival is
  /// not worth testing against.
  double _stableDelay(String busId) {
    final seed = _hash(busId);
    return (seed % 18) - 3.0;
  }

  /// Modelled occupancy for a simulated bus.
  ///
  /// Follows the same arch as [OccupancyEngine]: fullest shortly after the
  /// origin, emptying toward the destination.
  int _passengerCountFor(
      String busId, TransitService service, double journeyFraction) {
    final seats = service.serviceClass.seats;
    final seed = _hash('$busId|occupancy');
    final baseline = 0.45 + (seed % 40) / 100.0; // 0.45 – 0.85
    final arch = 1.0 - 2.0 * math.pow(journeyFraction.clamp(0.0, 1.0) - 0.3, 2);
    final load = (baseline * arch.clamp(0.35, 1.0)).clamp(0.0, 1.15);
    return (load * seats).round();
  }

  /// FNV-1a, so per-bus variation is stable across runs and platforms.
  int _hash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}

/// An interpolated simulator position.
class _SimPosition {
  final GeoPoint point;
  final double travelledKm;
  final double heading;
  final double speedKmph;

  /// Index of the route leg the bus is on.
  final int legIndex;
  final BusState state;

  const _SimPosition({
    required this.point,
    required this.travelledKm,
    required this.heading,
    required this.speedKmph,
    required this.legIndex,
    required this.state,
  });
}
