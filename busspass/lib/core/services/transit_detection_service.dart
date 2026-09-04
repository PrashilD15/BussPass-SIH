/// Transit detection: is the rider on a bus, and if so, which one?
///
/// This implements the decision tree from the implementation plan, which the old
/// codebase described in a design document and never built. The live navigation
/// screen pulsed a "Live Sync" badge over a hardcoded coordinate.
///
/// ## The problem
///
/// A phone's GPS cannot tell a bus from a car driving alongside it, and a single
/// position fix cannot tell either from a person standing still. Detection
/// therefore works on a **trail** — several minutes of position history — and
/// asks four questions in order, each cheap enough to answer before the next:
///
/// ```
/// 1. Sustained speed above 15 km/h for 2 minutes?
///      no  → STATIONARY
/// 2. Within 50 m of a bus route corridor?
///      no  → PRIVATE VEHICLE
/// 3. Does a live bus's position track the rider's?
///      no  → POSSIBLY ON BUS  (ask the rider)
/// 4. Sustained agreement under 100 m for 3 minutes?
///      yes → ON BOARD, bus identified
/// ```
///
/// ## Why each threshold
///
/// - **15 km/h** clears brisk walking and most cycling without needing a bus to
///   reach highway speed, so detection works in city traffic.
/// - **50 m** from the corridor is tight enough to exclude a parallel service
///   road, loose enough to absorb urban GPS multipath.
/// - **100 m** rider-to-bus is roughly three bus lengths: close enough to be the
///   same vehicle, loose enough to survive two independent GPS errors.
/// - **Sustained** windows are what make it robust. Any single sample can put a
///   pedestrian at 40 km/h or a bus 200 m off-route.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:busspass/core/math/geo.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';

/// A bus considered as a candidate match, with the evidence for it.
class BusMatch {
  final LiveBus bus;

  /// Current rider-to-bus distance, kilometres.
  final double distanceKm;

  /// Difference between the rider's and the bus's heading, degrees.
  final double headingDeltaDeg;

  /// How long the two have agreed within tolerance.
  final Duration agreementFor;

  /// 0 to 1.
  final double score;

  const BusMatch({
    required this.bus,
    required this.distanceKm,
    required this.headingDeltaDeg,
    required this.agreementFor,
    required this.score,
  });
}

class TransitDetector {
  TransitDetector({
    required this.network,
    this.config = TransitDetectionConfig.standard,
  });

  final TransitNetwork network;
  final TransitDetectionConfig config;

  final PositionTrail _trail = PositionTrail();

  /// Per-bus history of when agreement with the rider began.
  ///
  /// Keyed by bus id. Cleared when a bus drifts out of tolerance, which is what
  /// enforces the *sustained* requirement rather than a lucky single sample.
  final Map<String, DateTime> _agreementSince = {};

  /// The last emitted result, so a borderline reading does not flap the UI
  /// between two states every few seconds.
  TransitDetection _last = TransitDetection.unknown;

  PositionTrail get trail => _trail;

  /// Feed a rider position sample and get the current verdict.
  TransitDetection update({
    required GeoPoint point,
    required double speedKmph,
    required double heading,
    required DateTime at,
    required List<LiveBus> fleet,
  }) {
    _trail.add(TrailPoint(
      point: point,
      speedKmph: speedKmph,
      heading: heading,
      at: at,
    ));

    final result = _evaluate(point: point, at: at, fleet: fleet);
    _last = _stabilise(result);
    return _last;
  }

  /// Reset all state. Called when the rider ends a journey.
  void reset() {
    _trail.clear();
    _agreementSince.clear();
    _last = TransitDetection.unknown;
  }

  TransitDetection _evaluate({
    required GeoPoint point,
    required DateTime at,
    required List<LiveBus> fleet,
  }) {
    final currentSpeed = _trail.latest?.speedKmph ?? 0;

    // ── 1. Moving fast enough to be in a vehicle? ────────────────────────
    final sustained = _trail.sustainedAbove(config.vehicleSpeedKmph);
    if (sustained < config.sustainedFor) {
      // Not yet sustained. If the trail is simply too short, say so rather than
      // asserting the rider is stationary.
      final span = _trail.points.isEmpty
          ? Duration.zero
          : at.difference(_trail.points.first.at);
      if (span < config.sustainedFor) {
        return TransitDetection(
          status: TransitStatus.unknown,
          speedKmph: currentSpeed,
        );
      }
      return TransitDetection(
        status: TransitStatus.stationary,
        speedKmph: currentSpeed,
      );
    }

    // ── 2. On a bus corridor? ───────────────────────────────────────────
    final corridor = _nearestCorridor(point);
    if (corridor == null ||
        corridor.offsetKm > config.corridorToleranceKm) {
      return TransitDetection(
        status: TransitStatus.privateVehicle,
        speedKmph: currentSpeed,
        offRouteKm: corridor?.offsetKm,
        routeId: corridor?.routeId,
      );
    }

    // ── 3 and 4. Does a live bus track the rider? ───────────────────────
    final match = _bestMatch(point: point, at: at, fleet: fleet);

    if (match == null) {
      // On a corridor at bus speed, but nothing is reporting. The honest answer
      // is a question, not an assertion.
      return TransitDetection(
        status: TransitStatus.possiblyOnBus,
        speedKmph: currentSpeed,
        offRouteKm: corridor.offsetKm,
        routeId: corridor.routeId,
        confidence: 0.45,
      );
    }

    if (match.agreementFor < config.trailAgreementFor) {
      // A promising candidate that has not yet held for long enough.
      return TransitDetection(
        status: TransitStatus.possiblyOnBus,
        speedKmph: currentSpeed,
        bus: match.bus,
        distanceToBusKm: match.distanceKm,
        offRouteKm: corridor.offsetKm,
        routeId: match.bus.routeId,
        confidence: match.score * 0.7,
      );
    }

    return TransitDetection(
      status: TransitStatus.onBoard,
      speedKmph: currentSpeed,
      bus: match.bus,
      distanceToBusKm: match.distanceKm,
      offRouteKm: corridor.offsetKm,
      routeId: match.bus.routeId,
      confidence: match.score,
    );
  }

  /// Nearest route corridor to a point.
  ///
  /// Only routes whose bounding box contains the point are projected, because
  /// projecting all 270 corridors on every GPS tick would be wasteful — and this
  /// runs every 30 seconds for the whole time a rider is travelling.
  _CorridorHit? _nearestCorridor(GeoPoint point) {
    _CorridorHit? best;

    for (final route in network.routes) {
      final polyline = route.polyline;
      if (polyline.length < 2) continue;

      // Cheap rejection: a degree of latitude is ~111 km, so a 0.35° pad is a
      // generous ~39 km margin around the corridor.
      final box = Geo.bounds(polyline);
      if (box == null) continue;
      final (sw, ne) = box;
      const pad = 0.35;
      if (point.lat < sw.lat - pad ||
          point.lat > ne.lat + pad ||
          point.lng < sw.lng - pad ||
          point.lng > ne.lng + pad) {
        continue;
      }

      final projection = Geo.projectOnPolyline(point, polyline);
      if (projection == null) continue;

      if (best == null || projection.offsetKm < best.offsetKm) {
        best = _CorridorHit(
          routeId: route.id,
          offsetKm: projection.offsetKm,
          alongKm: projection.alongKm,
        );
      }
    }
    return best;
  }

  /// The best-matching bus, updating sustained-agreement bookkeeping.
  BusMatch? _bestMatch({
    required GeoPoint point,
    required DateTime at,
    required List<LiveBus> fleet,
  }) {
    final riderHeading = _trail.meanHeading;
    BusMatch? best;

    // Track which buses are in tolerance this tick, so the rest can have their
    // agreement streak cleared.
    final inTolerance = <String>{};

    for (final bus in fleet) {
      // A stale report cannot be matched: the bus may have moved kilometres.
      if (!bus.isFreshAt(at, threshold: const Duration(minutes: 3))) continue;
      // A bus at its origin or already arrived is not carrying this rider along
      // a corridor.
      if (bus.state == BusState.atOrigin ||
          bus.state == BusState.arrived ||
          bus.state == BusState.offService) {
        continue;
      }

      final distanceKm = Geo.distanceKm(point, bus.point);
      if (distanceKm > config.busMatchToleranceKm) continue;

      // Heading agreement rules out a bus on the opposite carriageway, which can
      // easily pass within 100 m.
      final headingDelta = Geo.bearingDelta(riderHeading, bus.heading);
      if (bus.state.isMoving && headingDelta > 55) continue;

      inTolerance.add(bus.id);
      final since = _agreementSince.putIfAbsent(bus.id, () => at);
      final agreementFor = at.difference(since);

      // Score blends proximity, heading agreement, and how long the two have
      // agreed. Duration is weighted most heavily because it is the hardest
      // evidence to obtain by coincidence.
      final proximityScore =
          1.0 - (distanceKm / config.busMatchToleranceKm).clamp(0.0, 1.0);
      final headingScore = 1.0 - (headingDelta / 90).clamp(0.0, 1.0);
      final durationScore = (agreementFor.inSeconds /
              config.trailAgreementFor.inSeconds)
          .clamp(0.0, 1.0);
      final score = proximityScore * 0.25 +
          headingScore * 0.2 +
          durationScore * 0.55;

      if (best == null || score > best.score) {
        best = BusMatch(
          bus: bus,
          distanceKm: distanceKm,
          headingDeltaDeg: headingDelta,
          agreementFor: agreementFor,
          score: score,
        );
      }
    }

    // Any bus that fell out of tolerance loses its streak.
    _agreementSince.removeWhere((id, _) => !inTolerance.contains(id));

    return best;
  }

  /// Hysteresis, so the UI does not flap.
  ///
  /// Once a rider is confirmed on board, a single bad GPS sample must not eject
  /// them — but a genuine loss of signal must not keep asserting a match either.
  /// The compromise: hold `onBoard` through transient degradation to
  /// `possiblyOnBus`, but release it on a clear `stationary` or
  /// `privateVehicle` verdict.
  TransitDetection _stabilise(TransitDetection next) {
    if (_last.status != TransitStatus.onBoard) return next;

    if (next.status == TransitStatus.possiblyOnBus ||
        next.status == TransitStatus.unknown) {
      // Keep the previous match, but report reduced confidence so the UI can
      // show a "reacquiring" state.
      return TransitDetection(
        status: TransitStatus.onBoard,
        speedKmph: next.speedKmph,
        bus: next.bus ?? _last.bus,
        distanceToBusKm: next.distanceToBusKm ?? _last.distanceToBusKm,
        offRouteKm: next.offRouteKm,
        routeId: next.routeId ?? _last.routeId,
        confidence: (_last.confidence * 0.8).clamp(0.0, 1.0),
      );
    }
    return next;
  }
}

/// A corridor projection result.
class _CorridorHit {
  final String routeId;
  final double offsetKm;
  final double alongKm;

  const _CorridorHit({
    required this.routeId,
    required this.offsetKm,
    required this.alongKm,
  });
}

/// Progress along a journey the rider is actually on.
///
/// Derived from a real position projected onto the real route geometry. Every
/// number here was previously a literal: progress was `0.35`, the next stop was
/// `'Lonavala Toll Plaza'`, and the ETA was `'ETA: 11:10 AM'`.
class JourneyProgress {
  final TransitRoute route;

  /// Distance covered from the boarding stop, kilometres.
  final double travelledKm;

  /// Distance still to go to the alighting stop, kilometres.
  final double remainingKm;

  /// 0 to 1 between boarding and alighting.
  final double fraction;

  /// The next stop the bus will call at.
  final RouteStopRef? nextStop;

  /// Distance to that stop, kilometres.
  final double? nextStopKm;

  /// Stops still to come before alighting.
  final int remainingStops;

  /// How far the rider is from the route corridor, kilometres. A large value
  /// means the match is wrong or the bus has diverted.
  final double offRouteKm;

  const JourneyProgress({
    required this.route,
    required this.travelledKm,
    required this.remainingKm,
    required this.fraction,
    required this.nextStop,
    required this.nextStopKm,
    required this.remainingStops,
    required this.offRouteKm,
  });

  bool get isApproachingDestination => remainingKm < 3;

  /// Compute progress for a rider between two stops on a route.
  ///
  /// Returns null when the position cannot be projected onto the route at all.
  static JourneyProgress? compute({
    required TransitRoute route,
    required GeoPoint riderPoint,
    required int boardSeq,
    required int alightSeq,
  }) {
    final polyline = route.polyline;
    if (polyline.length < 2) return null;

    final projection = Geo.projectOnPolyline(riderPoint, polyline);
    if (projection == null) return null;

    final boardRef = route.stopRefBySeq(boardSeq);
    final alightRef = route.stopRefBySeq(alightSeq);
    if (boardRef == null || alightRef == null) return null;

    final alongKm = route.roadKmForProjection(projection);

    // The corridor is stored in ascending sequence order, so a journey against
    // that order has to be measured from the other end.
    final descending = alightSeq < boardSeq;

    final boardKm = boardRef.cumKm;
    final alightKm = alightRef.cumKm;

    final travelled = descending ? boardKm - alongKm : alongKm - boardKm;
    final total = (alightKm - boardKm).abs();
    final remaining = (total - travelled).clamp(0.0, total);

    // Stops between here and the destination.
    final upcoming = route.stops.where((stop) {
      if (descending) {
        return stop.seq < boardSeq &&
            stop.seq >= alightSeq &&
            stop.cumKm < alongKm;
      }
      return stop.seq > boardSeq &&
          stop.seq <= alightSeq &&
          stop.cumKm > alongKm;
    }).toList()
      ..sort((a, b) => descending
          ? b.cumKm.compareTo(a.cumKm)
          : a.cumKm.compareTo(b.cumKm));

    final next = upcoming.isEmpty ? null : upcoming.first;

    return JourneyProgress(
      route: route,
      travelledKm: travelled.clamp(0.0, total),
      remainingKm: remaining,
      fraction: total <= 0 ? 0 : (travelled / total).clamp(0.0, 1.0),
      nextStop: next,
      nextStopKm: next == null ? null : (next.cumKm - alongKm).abs(),
      remainingStops: upcoming.length,
      offRouteKm: projection.offsetKm,
    );
  }

}

/// Wires the detector to position and fleet streams.
///
/// Owns the subscriptions and the debouncing, so the UI layer only ever sees a
/// stream of verdicts. Sampling is throttled to `config.sampleInterval` because
/// the OS position stream can fire far more often than detection needs, and each
/// evaluation projects against route geometry.
class TransitDetectionService {
  TransitDetectionService({
    required TransitNetwork network,
    TransitDetectionConfig config = TransitDetectionConfig.standard,
  })  : _detector = TransitDetector(network: network, config: config),
        _config = config;

  final TransitDetector _detector;
  final TransitDetectionConfig _config;

  final _controller = StreamController<TransitDetection>.broadcast();

  DateTime? _lastSample;
  List<LiveBus> _fleet = const [];

  Stream<TransitDetection> get detections => _controller.stream;

  TransitDetection get current => _detector._last;

  /// Update the fleet the detector matches against.
  void updateFleet(List<LiveBus> fleet) => _fleet = fleet;

  /// Feed a position sample.
  void addPosition({
    required GeoPoint point,
    required double speedKmph,
    required double heading,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();

    // Throttle: honour the configured sample interval regardless of how fast the
    // OS delivers fixes.
    final last = _lastSample;
    if (last != null && now.difference(last) < _config.sampleInterval) return;
    _lastSample = now;

    try {
      final detection = _detector.update(
        point: point,
        speedKmph: speedKmph,
        heading: heading,
        at: now,
        fleet: _fleet,
      );
      if (!_controller.isClosed) _controller.add(detection);
    } catch (error, stack) {
      // Detection is an enhancement. A failure must never take down navigation.
      debugPrint('TransitDetectionService: evaluation failed — $error');
      assert(() {
        debugPrintStack(stackTrace: stack, label: 'transit detection');
        return true;
      }());
    }
  }

  void reset() => _detector.reset();

  Future<void> dispose() async {
    await _controller.close();
  }
}
