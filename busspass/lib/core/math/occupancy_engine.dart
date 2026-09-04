/// Crowding estimation.
///
/// Two sources, in priority order:
///
/// 1. **Reported occupancy** — the conductor's POS knows exactly how many
///    tickets are live on the bus (`passengerCount` on the RTDB bus node). When
///    present this is ground truth.
/// 2. **Modelled occupancy** — when no bus is reporting, load is inferred from
///    the shape of demand: peak commuting windows, weekday vs weekend, distance
///    from the origin terminus, and service class.
///
/// The distinction matters and is surfaced to the rider. "43 of 45 seats taken"
/// is actionable; a modelled estimate presented with the same confidence is
/// misleading, so [OccupancyEstimate.isReported] gates how the UI phrases it.
library;

import 'dart:math' as math;

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/schedule.dart';

/// Rider-facing crowding bands.
enum CrowdLevel {
  /// Plenty of seats.
  empty('Seats available', 0.0),

  /// Filling but comfortable.
  light('Filling up', 0.35),

  /// Most seats taken.
  moderate('Mostly full', 0.65),

  /// Seated capacity reached.
  full('Full', 0.90),

  /// Standing passengers beyond seated capacity.
  crushed('Standing only', 1.05);

  const CrowdLevel(this.label, this.threshold);

  final String label;

  /// Lower bound of the load factor for this band.
  final double threshold;

  /// Band for a given load factor (occupied / seats).
  static CrowdLevel fromLoadFactor(double loadFactor) {
    if (loadFactor >= CrowdLevel.crushed.threshold) return CrowdLevel.crushed;
    if (loadFactor >= CrowdLevel.full.threshold) return CrowdLevel.full;
    if (loadFactor >= CrowdLevel.moderate.threshold) return CrowdLevel.moderate;
    if (loadFactor >= CrowdLevel.light.threshold) return CrowdLevel.light;
    return CrowdLevel.empty;
  }

  bool get hasSeats => index <= CrowdLevel.moderate.index;
}

/// An occupancy figure with its provenance.
class OccupancyEstimate {
  /// Passengers on board.
  final int occupied;

  /// Seated capacity of the service class.
  final int capacity;

  /// `occupied / capacity`. May exceed 1 when standing.
  final double loadFactor;

  final CrowdLevel level;

  /// True when [occupied] came from a conductor's device rather than the model.
  final bool isReported;

  /// Seats still free. Zero once standing.
  final int seatsAvailable;

  const OccupancyEstimate({
    required this.occupied,
    required this.capacity,
    required this.loadFactor,
    required this.level,
    required this.isReported,
    required this.seatsAvailable,
  });

  /// Phrasing that does not overstate confidence in a modelled number.
  String get description => isReported
      ? '$occupied of $capacity seats taken'
      : 'Around ${(loadFactor * 100).round()}% full, based on typical demand';

  @override
  String toString() =>
      'OccupancyEstimate($occupied/$capacity, ${level.name}, '
      'reported: $isReported)';
}

class OccupancyEngine {
  OccupancyEngine._();

  /// Exact occupancy from a conductor's reported headcount.
  static OccupancyEstimate fromReported({
    required int passengerCount,
    required ServiceClass serviceClass,
  }) {
    final capacity = math.max(1, serviceClass.seats);
    final occupied = math.max(0, passengerCount);
    final loadFactor = occupied / capacity;
    return OccupancyEstimate(
      occupied: occupied,
      capacity: capacity,
      loadFactor: loadFactor,
      level: CrowdLevel.fromLoadFactor(loadFactor),
      isReported: true,
      seatsAvailable: math.max(0, capacity - occupied),
    );
  }

  /// Modelled occupancy when nothing is reporting.
  ///
  /// The load factor is the product of four independent multipliers against a
  /// baseline. Each is deliberately shallow — this is a demand shape, not a
  /// prediction, and pretending otherwise would be worse than useless.
  ///
  /// - **Peak factor**: morning and evening commuter windows fill buses.
  /// - **Weekend factor**: weekday commuting load exceeds Sunday leisure load,
  ///   except on pilgrimage corridors.
  /// - **Position factor**: a bus is fullest just after its origin terminus and
  ///   empties as it approaches the destination.
  /// - **Class factor**: premium classes are reserved, so they run closer to
  ///   capacity but never oversubscribed.
  static OccupancyEstimate model({
    required ServiceClass serviceClass,
    required DateTime at,
    double journeyFraction = 0.0,
    bool isPilgrimageRoute = false,
  }) {
    final capacity = math.max(1, serviceClass.seats);
    final minute = Schedule.minuteOfDay(at);

    // Baseline: MSRTC's published fleet-wide load factor sits around 60%.
    var load = 0.60;

    load *= _peakFactor(minute);
    load *= _weekendFactor(at.weekday, isPilgrimageRoute);
    load *= _positionFactor(journeyFraction);
    load *= _classFactor(serviceClass);

    // Reserved premium services cannot oversell seats; ordinary services can
    // and do carry standees.
    final ceiling = serviceClass.tier >= 3 ? 1.0 : 1.25;
    load = load.clamp(0.05, ceiling);

    final occupied = (load * capacity).round();
    return OccupancyEstimate(
      occupied: occupied,
      capacity: capacity,
      loadFactor: load,
      level: CrowdLevel.fromLoadFactor(load),
      isReported: false,
      seatsAvailable: math.max(0, capacity - occupied),
    );
  }

  /// Commuter peak multiplier.
  static double _peakFactor(int minuteOfDay) {
    if (Schedule.isWithinWindow(minuteOfDay, 7 * 60, 10 * 60)) return 1.45;
    if (Schedule.isWithinWindow(minuteOfDay, 17 * 60, 20 * 60)) return 1.40;
    if (Schedule.isWithinWindow(minuteOfDay, 10 * 60, 17 * 60)) return 0.85;
    if (Schedule.isWithinWindow(minuteOfDay, 23 * 60, 5 * 60)) return 0.55;
    return 1.0;
  }

  /// Day-of-week multiplier. Pilgrimage corridors (Shirdi, Pandharpur,
  /// Trimbakeshwar) invert the usual pattern — they peak at the weekend.
  static double _weekendFactor(int weekday, bool isPilgrimageRoute) {
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
    if (isPilgrimageRoute) return isWeekend ? 1.30 : 0.90;
    return isWeekend ? 0.80 : 1.05;
  }

  /// Position-along-route multiplier: a shallow arch peaking at ~30% of the way.
  static double _positionFactor(double journeyFraction) {
    final f = journeyFraction.clamp(0.0, 1.0);
    // Quadratic with its maximum at f = 0.3, normalised to 1.0 there.
    final arch = 1.0 - 2.2 * math.pow(f - 0.3, 2).toDouble();
    return arch.clamp(0.45, 1.0);
  }

  /// Service-class multiplier. Premium classes sell out; ordinary buses carry
  /// whoever turns up.
  static double _classFactor(ServiceClass serviceClass) => switch (serviceClass.tier) {
        >= 4 => 0.92,
        3 => 0.95,
        2 => 1.0,
        _ => 1.10,
      };

  /// Whether a route serves a major pilgrimage destination, which changes the
  /// weekday/weekend demand shape.
  static bool isPilgrimageCorridor(String originCity, String destinationCity) {
    const pilgrimage = {
      'shirdi',
      'pandharpur',
      'trimbakeshwar',
      'tuljapur',
      'akkalkot',
      'paithan',
      'shegaon',
      'mahabaleshwar',
    };
    return pilgrimage.contains(originCity.toLowerCase()) ||
        pilgrimage.contains(destinationCity.toLowerCase());
  }
}
