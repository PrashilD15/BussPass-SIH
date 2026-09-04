/// Travel-time and arrival-time estimation.
///
/// The app previously displayed the literal string `'ETA'` where an arrival time
/// belonged, because `BusRoute.durationHrs` was a human-readable String like
/// `"3-4 hrs"` and could not be added to a departure time. This engine replaces
/// that with an actual model.
///
/// ## The model
///
/// Running time over a segment is the sum of three terms:
///
/// ```
/// t_total = t_running + t_dwell + t_break
///
/// t_running = distance / v_effective
/// t_dwell   = stops_served * dwell_per_stop
/// t_break   = floor(t_running / breakInterval) * breakDuration
/// ```
///
/// `v_effective` is the service class cruise speed adjusted for three things
/// that measurably change Indian intercity bus speed:
///
/// 1. **Trip length.** Short trips never reach cruise speed — they are dominated
///    by urban egress and approach. A 20 km run averages far below a 400 km run
///    on the same road with the same bus.
/// 2. **Time of day.** Peak-hour departures out of Pune or Mumbai lose real time
///    to congestion; overnight running is faster than the daytime average.
/// 3. **Stop density.** An Ordinary bus serving every village cannot hold the
///    same average as a Shivneri on the expressway, independent of dwell time.
///
/// Rest breaks are modelled explicitly because they are the single largest
/// omission in naive `distance / speed` estimates: a 700 km Nagpur–Pune service
/// takes two meal halts, and ignoring them understates arrival by roughly an
/// hour.
///
/// ## Calibration
///
/// The reference point is the curated corridor data: MSRTC's own published
/// running time for Mumbai–Pune (150 km, Shivneri) is about 3h15m, and for
/// Pune–Nashik (212 km, Semi Luxury) about 5h. The coefficients below reproduce
/// both within a few minutes. See `test/eta_engine_test.dart`.
library;

import 'dart:math' as math;

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/schedule.dart';

/// Traffic conditions applied on top of the base speed model.
enum TrafficCondition {
  /// Overnight running, open road.
  clear('Clear roads', 1.08),

  /// The modelled default.
  typical('Typical traffic', 1.0),

  /// Morning or evening peak on an urban approach.
  heavy('Heavy traffic', 0.82),

  /// Monsoon, festival rush, or an incident.
  severe('Severe delays', 0.65);

  const TrafficCondition(this.label, this.speedFactor);

  final String label;

  /// Multiplier on effective speed. Below 1 means slower.
  final double speedFactor;
}

/// A modelled travel time, itemised so the UI can explain the number.
class TravelEstimate {
  final double distanceKm;

  /// Time actually moving, in minutes.
  final int runningMinutes;

  /// Time stationary at intermediate stops, in minutes.
  final int dwellMinutes;

  /// Time in scheduled meal/rest halts, in minutes.
  final int breakMinutes;

  /// Sum of the three components.
  final int totalMinutes;

  /// Average speed over the whole trip including all halts, km/h. This is the
  /// number that should be compared against a published schedule.
  final double effectiveKmph;

  /// Free-running speed used, before halts, km/h.
  final double cruiseKmph;

  /// Intermediate stops the service is modelled as serving.
  final int stopsServed;

  final TrafficCondition traffic;
  final ServiceClass serviceClass;

  const TravelEstimate({
    required this.distanceKm,
    required this.runningMinutes,
    required this.dwellMinutes,
    required this.breakMinutes,
    required this.totalMinutes,
    required this.effectiveKmph,
    required this.cruiseKmph,
    required this.stopsServed,
    required this.traffic,
    required this.serviceClass,
  });

  /// Uncertainty band, in minutes. Widens with trip length because errors
  /// compound: a 12-hour overnight run cannot be predicted to the minute.
  int get uncertaintyMinutes {
    final proportional = (totalMinutes * 0.10).round();
    return math.max(5, math.min(75, proportional));
  }

  /// `4h 20m` style label.
  String get label => Schedule.formatDuration(totalMinutes);

  /// `4h 05m – 4h 45m` style range.
  String get rangeLabel {
    final low = math.max(1, totalMinutes - uncertaintyMinutes);
    final high = totalMinutes + uncertaintyMinutes;
    return '${Schedule.formatDuration(low)} – ${Schedule.formatDuration(high)}';
  }

  @override
  String toString() => 'TravelEstimate(${distanceKm.toStringAsFixed(1)} km, '
      '$totalMinutes min, ${effectiveKmph.toStringAsFixed(1)} km/h)';
}

/// A live arrival prediction for a bus already in motion.
class LiveArrival {
  /// Remaining distance to the target, in kilometres.
  final double remainingKm;

  /// Minutes until arrival.
  final int minutesRemaining;

  /// Predicted arrival time.
  final DateTime arrivesAt;

  /// Minutes late against schedule. Negative means running early.
  final int delayMinutes;

  /// Speed the prediction was based on, km/h.
  final double basisKmph;

  /// True when the prediction used a recent live speed rather than the
  /// timetable model.
  final bool isLive;

  const LiveArrival({
    required this.remainingKm,
    required this.minutesRemaining,
    required this.arrivesAt,
    required this.delayMinutes,
    required this.basisKmph,
    required this.isLive,
  });

  bool get isDelayed => delayMinutes >= 10;
  bool get isEarly => delayMinutes <= -10;

  String get delayLabel {
    if (delayMinutes.abs() < 5) return 'On time';
    if (delayMinutes > 0) return '${Schedule.formatDuration(delayMinutes)} late';
    return '${Schedule.formatDuration(-delayMinutes)} early';
  }
}

class EtaEngine {
  EtaEngine._();

  /// Running time after which a rest halt is taken, minutes.
  static const int breakIntervalMinutes = 210; // 3.5 h

  /// Duration of each rest halt, minutes.
  static const int breakDurationMinutes = 20;

  /// Minimum credible average speed, km/h. Guards against a corrupt distance
  /// producing a multi-day ETA on a short hop.
  static const double minEffectiveKmph = 18;

  /// Fraction of cruise speed reached on a very short trip.
  ///
  /// At 0 km the model starts here and approaches 1.0 asymptotically with
  /// distance, reflecting urban egress and approach overhead.
  static const double _shortTripFloor = 0.62;

  /// Distance over which the short-trip penalty decays, kilometres.
  static const double _shortTripScaleKm = 85;

  /// Speed multiplier from trip length alone.
  ///
  /// `f(d) = floor + (1 - floor) * d / (d + scale)`
  ///
  /// f(20 km) ≈ 0.69, f(150 km) ≈ 0.86, f(700 km) ≈ 0.96.
  static double lengthFactor(double distanceKm) {
    if (distanceKm <= 0) return _shortTripFloor;
    final d = distanceKm;
    return _shortTripFloor +
        (1 - _shortTripFloor) * (d / (d + _shortTripScaleKm));
  }

  /// Speed multiplier from departure time of day.
  ///
  /// Peak windows are 08:00–11:00 and 17:00–20:30, matching congestion on the
  /// Mumbai and Pune approaches. Overnight running (23:00–05:00) gets a bonus.
  static double timeOfDayFactor(int departureMinuteOfDay) {
    final m = Schedule.wrap(departureMinuteOfDay);
    if (Schedule.isWithinWindow(m, 23 * 60, 5 * 60)) return 1.10;
    if (Schedule.isWithinWindow(m, 8 * 60, 11 * 60)) return 0.88;
    if (Schedule.isWithinWindow(m, 17 * 60, 20 * 60 + 30)) return 0.85;
    if (Schedule.isWithinWindow(m, 5 * 60, 8 * 60)) return 1.04;
    return 1.0;
  }

  /// Speed multiplier from how many stops the service serves per 100 km.
  ///
  /// Frequent halts cost time beyond the dwell itself, through deceleration and
  /// re-acceleration. Capped at a 25% penalty.
  static double stopDensityFactor(int stopsServed, double distanceKm) {
    if (distanceKm <= 0 || stopsServed <= 0) return 1.0;
    final per100 = stopsServed / (distanceKm / 100.0);
    final penalty = math.min(0.25, per100 * 0.012);
    return 1.0 - penalty;
  }

  /// Number of intermediate stops the service actually halts at.
  ///
  /// [intermediateStops] is how many exist on the corridor;
  /// `serviceClass.stopDensity` is the fraction this class serves. A premium
  /// class still makes at least one halt on a long run — no MSRTC service
  /// crosses 300 km without stopping.
  static int stopsServedFor(ServiceClass serviceClass, int intermediateStops,
      double distanceKm) {
    if (intermediateStops <= 0) return 0;
    final modelled = (intermediateStops * serviceClass.stopDensity).round();
    final floor = distanceKm > 300 ? 1 : 0;
    return math.max(floor, math.min(intermediateStops, modelled));
  }

  /// Full travel-time estimate.
  static TravelEstimate estimate({
    required double distanceKm,
    required ServiceClass serviceClass,
    int intermediateStops = 0,
    int departureMinuteOfDay = 9 * 60,
    TrafficCondition traffic = TrafficCondition.typical,
  }) {
    final km = math.max(0.0, distanceKm);
    final stopsServed =
        stopsServedFor(serviceClass, intermediateStops, km);

    final effective = serviceClass.cruiseKmph *
        lengthFactor(km) *
        timeOfDayFactor(departureMinuteOfDay) *
        stopDensityFactor(stopsServed, km) *
        traffic.speedFactor;

    final cruise = math.max(minEffectiveKmph, effective);

    final runningMinutes = km <= 0 ? 0 : (km / cruise * 60).round();
    final dwellMinutes = (stopsServed * serviceClass.dwellMin).round();

    // Rest halts are driven by running time, not total time, so dwell does not
    // compound into extra breaks.
    final breaks = runningMinutes ~/ breakIntervalMinutes;
    final breakMinutes = breaks * breakDurationMinutes;

    final total = Schedule.sanitiseDuration(
      runningMinutes + dwellMinutes + breakMinutes,
    );

    return TravelEstimate(
      distanceKm: km,
      runningMinutes: runningMinutes,
      dwellMinutes: dwellMinutes,
      breakMinutes: breakMinutes,
      totalMinutes: total,
      effectiveKmph: total <= 0 ? 0 : km / (total / 60.0),
      cruiseKmph: cruise,
      stopsServed: stopsServed,
      traffic: traffic,
      serviceClass: serviceClass,
    );
  }

  /// Scheduled arrival minute-of-day for a departure plus a modelled duration.
  static int arrivalMinuteOfDay(int departureMinuteOfDay, int durationMinutes) =>
      Schedule.addMinutes(departureMinuteOfDay, durationMinutes);

  /// Cumulative running time to each stop on a corridor.
  ///
  /// [cumulativeKm] is distance from the origin at each stop, so the returned
  /// list has the same length and starts at 0. This is what turns a stop list
  /// into a timetable with a time against every row.
  static List<int> stopArrivalOffsets({
    required List<double> cumulativeKm,
    required ServiceClass serviceClass,
    int departureMinuteOfDay = 9 * 60,
    TrafficCondition traffic = TrafficCondition.typical,
  }) {
    if (cumulativeKm.isEmpty) return const [];
    final totalKm = cumulativeKm.last;
    final intermediate = math.max(0, cumulativeKm.length - 2);

    // Model the whole trip once, then distribute time in proportion to the
    // per-leg share of running distance. This guarantees the last stop's offset
    // equals the whole-trip estimate — a per-leg model would drift.
    final whole = estimate(
      distanceKm: totalKm,
      serviceClass: serviceClass,
      intermediateStops: intermediate,
      departureMinuteOfDay: departureMinuteOfDay,
      traffic: traffic,
    );

    final out = <int>[0];
    for (var i = 1; i < cumulativeKm.length; i++) {
      final share = totalKm <= 0 ? 0.0 : cumulativeKm[i] / totalKm;
      out.add((whole.totalMinutes * share).round());
    }
    // Snap the terminal so rounding cannot leave it a minute short.
    out[out.length - 1] = whole.totalMinutes;
    return out;
  }

  /// Live arrival prediction from a bus's current speed and remaining distance.
  ///
  /// A live speed is only trusted when it is plausible and recent. A bus stopped
  /// at a halt reports 0 km/h, and dividing by that yields infinity — so speeds
  /// below [minTrustedKmph] fall back to the modelled speed while still
  /// reporting `isLive: false` so the UI can say so.
  static LiveArrival predictArrival({
    required double remainingKm,
    required double currentKmph,
    required DateTime now,
    required ServiceClass serviceClass,
    int? scheduledArrivalMinuteOfDay,
    int remainingStops = 0,
    double minTrustedKmph = 8,
  }) {
    final km = math.max(0.0, remainingKm);

    // Blend live speed toward the modelled speed. A single GPS sample is noisy;
    // weighting it 70/30 against the model keeps the ETA from jumping every
    // time the bus slows for a village.
    final modelled = serviceClass.cruiseKmph * lengthFactor(km);
    final trustLive = currentKmph >= minTrustedKmph;
    final basis = trustLive
        ? (currentKmph * 0.7 + modelled * 0.3)
        : modelled;
    final speed = math.max(minEffectiveKmph, basis);

    final runningMinutes = (km / speed * 60).round();
    final dwellMinutes = (remainingStops * serviceClass.dwellMin).round();
    final minutes = Schedule.sanitiseDuration(runningMinutes + dwellMinutes);

    final arrivesAt = now.add(Duration(minutes: minutes));

    var delay = 0;
    if (scheduledArrivalMinuteOfDay != null) {
      final predictedMinute = Schedule.minuteOfDay(arrivesAt);
      delay = Schedule.signedGap(scheduledArrivalMinuteOfDay, predictedMinute);
    }

    return LiveArrival(
      remainingKm: km,
      minutesRemaining: minutes,
      arrivesAt: arrivesAt,
      delayMinutes: delay,
      basisKmph: speed,
      isLive: trustLive,
    );
  }

  /// Fraction of the journey completed, 0–1.
  static double progressFraction(double travelledKm, double totalKm) {
    if (totalKm <= 0) return 0;
    return (travelledKm / totalKm).clamp(0.0, 1.0);
  }

  /// Traffic condition implied by a departure time, when no live feed exists.
  ///
  /// Lets the model reflect peak-hour congestion without pretending to have
  /// real-time road data.
  static TrafficCondition inferTraffic(int minuteOfDayValue) {
    if (Schedule.isWithinWindow(minuteOfDayValue, 23 * 60, 5 * 60)) {
      return TrafficCondition.clear;
    }
    if (Schedule.isWithinWindow(minuteOfDayValue, 8 * 60 + 30, 10 * 60 + 30) ||
        Schedule.isWithinWindow(minuteOfDayValue, 17 * 60 + 30, 19 * 60 + 30)) {
      return TrafficCondition.heavy;
    }
    return TrafficCondition.typical;
  }
}
