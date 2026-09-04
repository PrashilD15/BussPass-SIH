/// Live bus positions.
///
/// One model, two sources, deliberately interchangeable:
///
///  - **Firebase RTDB** at `buses/{busId}`, written by the POS device paired
///    with a hardwired GPS module. This is the production path.
///  - **A deterministic in-app simulator** that advances buses along real route
///    polylines on real schedules. This is what makes the live map, live ETA, and
///    transit detection genuinely exercisable without hardware.
///
/// Both produce [LiveBus], so nothing downstream knows or cares which is active.
/// Swapping to real hardware is a provider change, not a rewrite.
library;

import 'dart:math' as math;

import 'package:busspass/core/math/geo.dart';

/// Operational state of a bus.
enum BusState {
  /// Waiting at its origin terminus before departure.
  atOrigin('At origin', 'Waiting to depart'),

  /// Moving between stops.
  inTransit('In transit', 'On the way'),

  /// Stopped at an intermediate stop, boarding.
  atStop('At stop', 'Passengers boarding'),

  /// On a scheduled meal or rest break.
  onBreak('Rest halt', 'Scheduled rest stop'),

  /// Arrived at its destination.
  arrived('Arrived', 'Journey complete'),

  /// Not running.
  offService('Not in service', 'This bus is off duty');

  const BusState(this.label, this.description);
  final String label;
  final String description;

  bool get isMoving => this == inTransit;
  bool get isStopped => this == atStop || this == onBreak;
}

/// A bus reporting its position.
class LiveBus {
  /// Registration plate, e.g. `MH12AB1234`. Also the RTDB node key.
  final String id;

  final String routeId;
  final String serviceId;
  final String busType;

  final double lat;
  final double lng;

  /// Ground speed, km/h.
  final double speedKmph;

  /// Heading, degrees clockwise from north.
  final double heading;

  /// Distance travelled from the route origin, kilometres. This is the value the
  /// ETA and progress engines actually consume.
  final double travelledKm;

  /// Sequence number of the next stop on the route.
  final int nextStopSeq;

  /// Passengers on board, when the conductor's device is reporting. Null means
  /// occupancy has to be modelled instead.
  final int? passengerCount;

  final BusState state;

  /// When this position was reported.
  final DateTime updatedAt;

  /// Scheduled departure of this run, so delay can be computed.
  final DateTime scheduledDeparture;

  /// True when the position came from a simulator rather than a real device.
  /// Surfaced in the UI — presenting simulated data as live telemetry would be
  /// dishonest.
  final bool isSimulated;

  const LiveBus({
    required this.id,
    required this.routeId,
    required this.serviceId,
    required this.busType,
    required this.lat,
    required this.lng,
    required this.speedKmph,
    required this.heading,
    required this.travelledKm,
    required this.nextStopSeq,
    required this.state,
    required this.updatedAt,
    required this.scheduledDeparture,
    this.passengerCount,
    this.isSimulated = false,
  });

  GeoPoint get point => GeoPoint(lat, lng);

  /// Age of this position report.
  Duration ageAt(DateTime now) => now.difference(updatedAt);

  /// Whether the report is recent enough to plot as live.
  ///
  /// A POS device on a patchy highway link goes quiet for minutes at a time. The
  /// honest response is a staleness label, not a vanished bus.
  bool isFreshAt(DateTime now, {Duration threshold = const Duration(minutes: 2)}) =>
      ageAt(now) <= threshold;

  /// Human phrasing for staleness, matching the plan's "Last updated X minutes
  /// ago" requirement.
  String freshnessLabel(DateTime now) {
    final age = ageAt(now);
    if (age.inSeconds < 30) return 'Live';
    if (age.inMinutes < 1) return 'Updated ${age.inSeconds}s ago';
    if (age.inMinutes < 60) return 'Updated ${age.inMinutes} min ago';
    return 'Signal lost';
  }

  LiveBus copyWith({
    double? lat,
    double? lng,
    double? speedKmph,
    double? heading,
    double? travelledKm,
    int? nextStopSeq,
    int? passengerCount,
    BusState? state,
    DateTime? updatedAt,
  }) =>
      LiveBus(
        id: id,
        routeId: routeId,
        serviceId: serviceId,
        busType: busType,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        speedKmph: speedKmph ?? this.speedKmph,
        heading: heading ?? this.heading,
        travelledKm: travelledKm ?? this.travelledKm,
        nextStopSeq: nextStopSeq ?? this.nextStopSeq,
        passengerCount: passengerCount ?? this.passengerCount,
        state: state ?? this.state,
        updatedAt: updatedAt ?? this.updatedAt,
        scheduledDeparture: scheduledDeparture,
        isSimulated: isSimulated,
      );

  /// RTDB shape, matching the schema in the implementation plan.
  Map<String, dynamic> toRtdb() => {
        'lat': lat,
        'lng': lng,
        'speed': speedKmph,
        'heading': heading.round(),
        'routeId': routeId,
        'serviceId': serviceId,
        'busType': busType,
        'travelledKm': travelledKm,
        'nextStopSeq': nextStopSeq,
        'status': state.name,
        'lastUpdated': updatedAt.millisecondsSinceEpoch ~/ 1000,
        'scheduledDeparture':
            scheduledDeparture.millisecondsSinceEpoch ~/ 1000,
        if (passengerCount != null) 'passengerCount': passengerCount,
      };

  /// Parse an RTDB node.
  ///
  /// Returns null on a malformed node rather than throwing: one bad bus must not
  /// blank the whole map.
  static LiveBus? fromRtdb(String id, Map<Object?, Object?> raw) {
    double? number(String key) {
      final value = raw[key];
      return value is num ? value.toDouble() : null;
    }

    final lat = number('lat');
    final lng = number('lng');
    if (lat == null || lng == null) return null;

    final lastUpdated = number('lastUpdated');
    final scheduled = number('scheduledDeparture');

    return LiveBus(
      id: id,
      routeId: raw['routeId'] as String? ?? '',
      serviceId: raw['serviceId'] as String? ?? '',
      busType: raw['busType'] as String? ?? 'Ordinary',
      lat: lat,
      lng: lng,
      speedKmph: number('speed') ?? 0,
      heading: number('heading') ?? 0,
      travelledKm: number('travelledKm') ?? 0,
      nextStopSeq: number('nextStopSeq')?.toInt() ?? 0,
      passengerCount: number('passengerCount')?.toInt(),
      state: BusState.values.firstWhere(
        (s) => s.name == raw['status'],
        orElse: () => BusState.inTransit,
      ),
      updatedAt: lastUpdated == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(
              (lastUpdated * 1000).round()),
      scheduledDeparture: scheduled == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch((scheduled * 1000).round()),
    );
  }

  @override
  bool operator ==(Object other) => other is LiveBus && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'LiveBus($id, ${travelledKm.toStringAsFixed(1)} km, ${state.name})';
}

/// Whether the rider appears to be aboard a bus, and which one.
///
/// This implements the decision tree from the implementation plan. The old code
/// had no implementation at all; "Live Sync" pulsed over a hardcoded coordinate.
///
/// The logic, in order:
///  1. Speed below the walking/cycling threshold → stationary.
///  2. Moving, but not near any route corridor → private vehicle.
///  3. Near a corridor, but no bus's GPS trail matches → prompt the rider.
///  4. A bus trail matches within the deviation tolerance → on board, identified.
class TransitDetection {
  final TransitStatus status;

  /// The matched bus, when [status] is [TransitStatus.onBoard].
  final LiveBus? bus;

  /// Distance from the rider to the matched bus, kilometres.
  final double? distanceToBusKm;

  /// Perpendicular distance from the rider to the nearest route corridor,
  /// kilometres.
  final double? offRouteKm;

  /// Route the rider appears to be travelling along.
  final String? routeId;

  /// Rider's current speed, km/h.
  final double speedKmph;

  /// Confidence in the match, 0 to 1.
  final double confidence;

  const TransitDetection({
    required this.status,
    required this.speedKmph,
    this.bus,
    this.distanceToBusKm,
    this.offRouteKm,
    this.routeId,
    this.confidence = 0,
  });

  static const TransitDetection unknown = TransitDetection(
    status: TransitStatus.unknown,
    speedKmph: 0,
  );

  bool get isOnBoard => status == TransitStatus.onBoard;

  /// True when the app should ask "are you on a bus?" rather than assert it.
  bool get shouldPrompt => status == TransitStatus.possiblyOnBus;
}

/// Result of transit detection.
enum TransitStatus {
  /// Not enough data yet.
  unknown('Checking…'),

  /// Not moving.
  stationary('Not travelling'),

  /// Moving, but away from any bus corridor.
  privateVehicle('Travelling by road'),

  /// On a corridor at bus speed, but no bus matched.
  possiblyOnBus('Are you on a bus?'),

  /// Matched to a specific bus.
  onBoard('On board');

  const TransitStatus(this.label);
  final String label;
}

/// Thresholds for transit detection, taken from the implementation plan.
class TransitDetectionConfig {
  /// Sustained speed above which the rider is in a vehicle, km/h.
  final double vehicleSpeedKmph;

  /// How long that speed must be sustained.
  final Duration sustainedFor;

  /// Maximum perpendicular distance from a route corridor to count as "on the
  /// corridor", kilometres.
  final double corridorToleranceKm;

  /// Maximum distance between rider and bus to call it a match, kilometres.
  final double busMatchToleranceKm;

  /// How long the trails must agree before asserting a match.
  final Duration trailAgreementFor;

  /// GPS sample interval.
  final Duration sampleInterval;

  const TransitDetectionConfig({
    this.vehicleSpeedKmph = 15,
    this.sustainedFor = const Duration(minutes: 2),
    this.corridorToleranceKm = 0.05,
    this.busMatchToleranceKm = 0.1,
    this.trailAgreementFor = const Duration(minutes: 3),
    this.sampleInterval = const Duration(seconds: 30),
  });

  static const TransitDetectionConfig standard = TransitDetectionConfig();
}

/// A rider position sample, retained to build a trail.
class TrailPoint {
  final GeoPoint point;
  final double speedKmph;
  final double heading;
  final DateTime at;

  const TrailPoint({
    required this.point,
    required this.speedKmph,
    required this.heading,
    required this.at,
  });
}

/// A rolling window of rider positions.
///
/// Detection needs history, not a single fix: one GPS sample cannot distinguish
/// a bus from a car alongside it, but three minutes of agreement can.
class PositionTrail {
  final List<TrailPoint> _points = [];

  /// How much history to keep.
  final Duration window;

  PositionTrail({this.window = const Duration(minutes: 8)});

  List<TrailPoint> get points => List.unmodifiable(_points);

  bool get isEmpty => _points.isEmpty;

  TrailPoint? get latest => _points.isEmpty ? null : _points.last;

  void add(TrailPoint point) {
    _points.add(point);
    final cutoff = point.at.subtract(window);
    _points.removeWhere((p) => p.at.isBefore(cutoff));
  }

  void clear() => _points.clear();

  /// Mean speed over the trail, km/h.
  double get averageSpeedKmph {
    if (_points.isEmpty) return 0;
    final total = _points.fold<double>(0, (sum, p) => sum + p.speedKmph);
    return total / _points.length;
  }

  /// How long the rider has continuously exceeded [kmph].
  ///
  /// Walks backwards from the newest sample and stops at the first slower one,
  /// so a single stop at a traffic light resets the streak — which is correct,
  /// because a bus at a stop is also slow.
  Duration sustainedAbove(double kmph) {
    if (_points.length < 2) return Duration.zero;
    DateTime? streakStart;
    for (var i = _points.length - 1; i >= 0; i--) {
      if (_points[i].speedKmph < kmph) break;
      streakStart = _points[i].at;
    }
    if (streakStart == null) return Duration.zero;
    return _points.last.at.difference(streakStart);
  }

  /// Distance covered along the trail, kilometres.
  double get distanceKm {
    if (_points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      total += Geo.distanceKm(_points[i - 1].point, _points[i].point);
    }
    return total;
  }

  /// Mean heading, computed as a circular mean.
  ///
  /// A plain arithmetic mean of 350° and 10° gives 180° — the exact opposite of
  /// the true answer. Averaging the unit vectors avoids that.
  double get meanHeading {
    if (_points.isEmpty) return 0;
    var x = 0.0;
    var y = 0.0;
    for (final p in _points) {
      final radians = p.heading * math.pi / 180;
      x += math.cos(radians);
      y += math.sin(radians);
    }
    final degrees = math.atan2(y, x) * 180 / math.pi;
    return (degrees + 360) % 360;
  }
}
