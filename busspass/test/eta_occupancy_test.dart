import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/eta_engine.dart';
import 'package:busspass/core/math/occupancy_engine.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';

void main() {
  final ordinary = ServiceClassCatalog.byKey('Ordinary');
  final semiLuxury = ServiceClassCatalog.byKey('Semi Luxury');
  final shivneri = ServiceClassCatalog.byKey('Shivneri');

  group('length factor', () {
    test('short trips never reach cruise speed', () {
      expect(EtaEngine.lengthFactor(0), lessThan(0.7));
      expect(EtaEngine.lengthFactor(20), lessThan(0.75));
    });

    test('approaches one as distance grows', () {
      expect(EtaEngine.lengthFactor(700), greaterThan(0.93));
      expect(EtaEngine.lengthFactor(700), lessThan(1.0));
    });

    test('is monotonically increasing', () {
      var previous = 0.0;
      for (var km = 0.0; km <= 900; km += 25) {
        final factor = EtaEngine.lengthFactor(km);
        expect(factor, greaterThanOrEqualTo(previous));
        previous = factor;
      }
    });
  });

  group('time-of-day factor', () {
    test('overnight running is faster than the daytime average', () {
      expect(EtaEngine.timeOfDayFactor(1 * 60), greaterThan(1.0));
      expect(EtaEngine.timeOfDayFactor(23 * 60 + 30), greaterThan(1.0));
    });

    test('morning and evening peaks are slower', () {
      expect(EtaEngine.timeOfDayFactor(9 * 60), lessThan(1.0));
      expect(EtaEngine.timeOfDayFactor(18 * 60), lessThan(1.0));
    });

    test('midday is the baseline', () {
      expect(EtaEngine.timeOfDayFactor(13 * 60), 1.0);
    });

    test('handles out-of-range minutes by wrapping', () {
      expect(EtaEngine.timeOfDayFactor(1440 + 9 * 60),
          EtaEngine.timeOfDayFactor(9 * 60));
    });
  });

  group('stops served', () {
    test('a premium class skips most intermediate stops', () {
      expect(EtaEngine.stopsServedFor(shivneri, 10, 200),
          lessThan(EtaEngine.stopsServedFor(ordinary, 10, 200)));
    });

    test('an ordinary bus halts everywhere', () {
      expect(EtaEngine.stopsServedFor(ordinary, 8, 200), 8);
    });

    test('no service crosses 300 km without a single halt', () {
      // Guards a rounding path where a low stopDensity produced zero halts on a
      // 700 km run, which is not a real service pattern.
      expect(EtaEngine.stopsServedFor(shivneri, 1, 700),
          greaterThanOrEqualTo(1));
    });

    test('never exceeds the stops that exist', () {
      expect(EtaEngine.stopsServedFor(ordinary, 3, 400), lessThanOrEqualTo(3));
    });

    test('zero intermediate stops yields zero', () {
      expect(EtaEngine.stopsServedFor(ordinary, 0, 150), 0);
    });
  });

  group('travel estimate', () {
    test('reproduces the published Mumbai–Pune running time', () {
      // MSRTC Shivneri Mumbai–Pune (150 km) is timetabled around 3h15m.
      final estimate = EtaEngine.estimate(
        distanceKm: 150,
        serviceClass: shivneri,
        intermediateStops: 2,
        departureMinuteOfDay: 9 * 60,
      );
      expect(estimate.totalMinutes, inInclusiveRange(165, 230),
          reason: 'modelled ${estimate.totalMinutes} min');
    });

    test('reproduces the published Pune–Nashik running time', () {
      // Semi Luxury Pune–Nashik (212 km) runs about 5h.
      final estimate = EtaEngine.estimate(
        distanceKm: 212,
        serviceClass: semiLuxury,
        intermediateStops: 1,
        departureMinuteOfDay: 7 * 60,
      );
      expect(estimate.totalMinutes, inInclusiveRange(240, 330),
          reason: 'modelled ${estimate.totalMinutes} min');
    });

    test('components sum to the total', () {
      final estimate = EtaEngine.estimate(
        distanceKm: 430,
        serviceClass: ordinary,
        intermediateStops: 6,
      );
      expect(
        estimate.runningMinutes +
            estimate.dwellMinutes +
            estimate.breakMinutes,
        estimate.totalMinutes,
      );
    });

    test('a premium class is faster over the same distance', () {
      final slow = EtaEngine.estimate(
          distanceKm: 240, serviceClass: ordinary, intermediateStops: 5);
      final fast = EtaEngine.estimate(
          distanceKm: 240, serviceClass: shivneri, intermediateStops: 5);
      expect(fast.totalMinutes, lessThan(slow.totalMinutes));
    });

    test('duration grows with distance', () {
      var previous = 0;
      for (var km = 20.0; km <= 800; km += 40) {
        final estimate =
            EtaEngine.estimate(distanceKm: km, serviceClass: ordinary);
        expect(estimate.totalMinutes, greaterThan(previous));
        previous = estimate.totalMinutes;
      }
    });

    test('long runs include rest halts', () {
      final short =
          EtaEngine.estimate(distanceKm: 100, serviceClass: ordinary);
      final long = EtaEngine.estimate(distanceKm: 700, serviceClass: ordinary);
      expect(short.breakMinutes, 0);
      expect(long.breakMinutes, greaterThanOrEqualTo(
          EtaEngine.breakDurationMinutes));
    });

    test('heavy traffic slows the trip', () {
      final typical = EtaEngine.estimate(
          distanceKm: 150, serviceClass: ordinary);
      final heavy = EtaEngine.estimate(
          distanceKm: 150,
          serviceClass: ordinary,
          traffic: TrafficCondition.heavy);
      expect(heavy.totalMinutes, greaterThan(typical.totalMinutes));
    });

    test('effective speed stays in a credible band', () {
      for (final km in [10.0, 60.0, 150.0, 400.0, 840.0]) {
        for (final cls in ServiceClassCatalog.all) {
          final estimate = EtaEngine.estimate(
              distanceKm: km, serviceClass: cls, intermediateStops: 4);
          expect(estimate.effectiveKmph, inInclusiveRange(10.0, 70.0),
              reason: '$km km on ${cls.key} averaged '
                  '${estimate.effectiveKmph.toStringAsFixed(1)} km/h');
        }
      }
    });

    test('zero distance does not produce a negative or absurd duration', () {
      final estimate =
          EtaEngine.estimate(distanceKm: 0, serviceClass: ordinary);
      expect(estimate.totalMinutes, greaterThanOrEqualTo(1));
    });

    test('uncertainty widens with trip length but stays bounded', () {
      final short =
          EtaEngine.estimate(distanceKm: 30, serviceClass: ordinary);
      final long = EtaEngine.estimate(distanceKm: 800, serviceClass: ordinary);
      expect(short.uncertaintyMinutes, greaterThanOrEqualTo(5));
      expect(long.uncertaintyMinutes, greaterThan(short.uncertaintyMinutes));
      expect(long.uncertaintyMinutes, lessThanOrEqualTo(75));
    });

    test('range label brackets the point estimate', () {
      final estimate =
          EtaEngine.estimate(distanceKm: 240, serviceClass: semiLuxury);
      expect(estimate.rangeLabel, contains('–'));
      expect(estimate.label, isNotEmpty);
    });
  });

  group('arrival time', () {
    test('adds the duration to the departure', () {
      expect(EtaEngine.arrivalMinuteOfDay(9 * 60, 195), 12 * 60 + 15);
    });

    test('wraps across midnight', () {
      // 22:00 departure, 5 hours → 03:00 the next day.
      expect(EtaEngine.arrivalMinuteOfDay(22 * 60, 300), 3 * 60);
    });
  });

  group('per-stop arrival offsets', () {
    final cumulative = [0.0, 55.0, 110.0, 160.0];

    test('starts at zero', () {
      final offsets = EtaEngine.stopArrivalOffsets(
          cumulativeKm: cumulative, serviceClass: ordinary);
      expect(offsets.first, 0);
    });

    test('ends exactly at the whole-trip estimate', () {
      // A per-leg model drifts; distributing one whole-trip estimate does not.
      final offsets = EtaEngine.stopArrivalOffsets(
          cumulativeKm: cumulative, serviceClass: ordinary);
      final whole = EtaEngine.estimate(
        distanceKm: 160,
        serviceClass: ordinary,
        intermediateStops: 2,
      );
      expect(offsets.last, whole.totalMinutes);
    });

    test('is monotonically increasing', () {
      final offsets = EtaEngine.stopArrivalOffsets(
          cumulativeKm: cumulative, serviceClass: ordinary);
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], greaterThanOrEqualTo(offsets[i - 1]));
      }
    });

    test('has one entry per stop', () {
      final offsets = EtaEngine.stopArrivalOffsets(
          cumulativeKm: cumulative, serviceClass: ordinary);
      expect(offsets.length, cumulative.length);
    });

    test('an empty stop list yields an empty result', () {
      expect(
        EtaEngine.stopArrivalOffsets(
            cumulativeKm: const [], serviceClass: ordinary),
        isEmpty,
      );
    });

    test('offsets are roughly proportional to distance', () {
      final offsets = EtaEngine.stopArrivalOffsets(
          cumulativeKm: cumulative, serviceClass: ordinary);
      // The midpoint stop at 110 of 160 km should be at ~69% of the time.
      expect(offsets[2] / offsets.last, closeTo(110 / 160, 0.02));
    });
  });

  group('live arrival prediction', () {
    final now = DateTime(2026, 9, 3, 10, 0);

    test('uses the live speed when it is plausible', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 60,
        currentKmph: 55,
        now: now,
        serviceClass: semiLuxury,
      );
      expect(arrival.isLive, isTrue);
      expect(arrival.minutesRemaining, greaterThan(0));
      expect(arrival.arrivesAt.isAfter(now), isTrue);
    });

    test('a stopped bus does not divide by zero', () {
      // The bug this guards: a bus at a halt reports 0 km/h and a naive
      // distance/speed yields infinity.
      final arrival = EtaEngine.predictArrival(
        remainingKm: 60,
        currentKmph: 0,
        now: now,
        serviceClass: semiLuxury,
      );
      expect(arrival.minutesRemaining.isFinite, isTrue);
      expect(arrival.isLive, isFalse);
      expect(arrival.minutesRemaining, greaterThan(0));
    });

    test('a crawling bus falls back to the model', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 60,
        currentKmph: 3,
        now: now,
        serviceClass: semiLuxury,
      );
      expect(arrival.isLive, isFalse);
    });

    test('blends live speed toward the model so the ETA does not jump', () {
      // A single fast sample should not halve the ETA.
      final modelled = EtaEngine.predictArrival(
        remainingKm: 100,
        currentKmph: 0,
        now: now,
        serviceClass: ordinary,
      );
      final fast = EtaEngine.predictArrival(
        remainingKm: 100,
        currentKmph: 200,
        now: now,
        serviceClass: ordinary,
      );
      expect(fast.basisKmph, lessThan(200));
      expect(fast.basisKmph, greaterThan(modelled.basisKmph));
    });

    test('zero remaining distance arrives immediately', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 0,
        currentKmph: 40,
        now: now,
        serviceClass: ordinary,
      );
      expect(arrival.minutesRemaining, lessThanOrEqualTo(1));
    });

    test('remaining stops add dwell time', () {
      final noStops = EtaEngine.predictArrival(
        remainingKm: 80,
        currentKmph: 45,
        now: now,
        serviceClass: ordinary,
      );
      final withStops = EtaEngine.predictArrival(
        remainingKm: 80,
        currentKmph: 45,
        now: now,
        serviceClass: ordinary,
        remainingStops: 5,
      );
      expect(withStops.minutesRemaining,
          greaterThan(noStops.minutesRemaining));
    });

    test('reports delay against a schedule', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 40,
        currentKmph: 40,
        now: now,
        serviceClass: ordinary,
        // Predicted arrival is ~11:00; scheduled 10:30 means 30 min late.
        scheduledArrivalMinuteOfDay: 10 * 60 + 30,
      );
      expect(arrival.delayMinutes, greaterThan(15));
      expect(arrival.isDelayed, isTrue);
      expect(arrival.delayLabel, contains('late'));
    });

    test('reports running early', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 10,
        currentKmph: 50,
        now: now,
        serviceClass: shivneri,
        scheduledArrivalMinuteOfDay: 11 * 60,
      );
      expect(arrival.delayMinutes, lessThan(0));
      expect(arrival.isEarly, isTrue);
      expect(arrival.delayLabel, contains('early'));
    });

    test('delay is measured across midnight correctly', () {
      final lateNight = DateTime(2026, 9, 3, 23, 50);
      final arrival = EtaEngine.predictArrival(
        remainingKm: 5,
        currentKmph: 40,
        now: lateNight,
        serviceClass: ordinary,
        // Scheduled 23:45; predicted just after midnight → a few minutes late,
        // not 1,435 minutes early.
        scheduledArrivalMinuteOfDay: 23 * 60 + 45,
      );
      expect(arrival.delayMinutes.abs(), lessThan(60));
    });

    test('on-time is reported without a spurious delay', () {
      final arrival = EtaEngine.predictArrival(
        remainingKm: 30,
        currentKmph: 45,
        now: now,
        serviceClass: semiLuxury,
      );
      expect(arrival.delayMinutes, 0);
      expect(arrival.delayLabel, 'On time');
    });
  });

  group('progress fraction', () {
    test('is zero at the start and one at the end', () {
      expect(EtaEngine.progressFraction(0, 150), 0);
      expect(EtaEngine.progressFraction(150, 150), 1);
    });

    test('clamps beyond the endpoints', () {
      expect(EtaEngine.progressFraction(-10, 150), 0);
      expect(EtaEngine.progressFraction(200, 150), 1);
    });

    test('a zero-length route does not divide by zero', () {
      expect(EtaEngine.progressFraction(10, 0), 0);
    });

    test('is proportional in between', () {
      expect(EtaEngine.progressFraction(75, 150), closeTo(0.5, 1e-9));
    });
  });

  group('traffic inference', () {
    test('overnight is clear', () {
      expect(EtaEngine.inferTraffic(2 * 60), TrafficCondition.clear);
    });

    test('peak windows are heavy', () {
      expect(EtaEngine.inferTraffic(9 * 60), TrafficCondition.heavy);
      expect(EtaEngine.inferTraffic(18 * 60 + 30), TrafficCondition.heavy);
    });

    test('midday is typical', () {
      expect(EtaEngine.inferTraffic(13 * 60), TrafficCondition.typical);
    });
  });

  group('occupancy from a reported headcount', () {
    test('is marked as ground truth', () {
      final estimate = OccupancyEngine.fromReported(
          passengerCount: 38, serviceClass: ordinary);
      expect(estimate.isReported, isTrue);
      expect(estimate.occupied, 38);
      expect(estimate.capacity, ordinary.seats);
      expect(estimate.description, contains('38 of'));
    });

    test('computes seats available', () {
      final estimate = OccupancyEngine.fromReported(
          passengerCount: 40, serviceClass: semiLuxury);
      expect(estimate.seatsAvailable, semiLuxury.seats - 40);
    });

    test('an empty bus reads as empty', () {
      final estimate = OccupancyEngine.fromReported(
          passengerCount: 0, serviceClass: ordinary);
      expect(estimate.level, CrowdLevel.empty);
      expect(estimate.loadFactor, 0);
    });

    test('standing passengers exceed capacity without breaking', () {
      final estimate = OccupancyEngine.fromReported(
          passengerCount: 70, serviceClass: ordinary);
      expect(estimate.loadFactor, greaterThan(1));
      expect(estimate.level, CrowdLevel.crushed);
      expect(estimate.seatsAvailable, 0);
    });

    test('a negative count is clamped rather than trusted', () {
      final estimate = OccupancyEngine.fromReported(
          passengerCount: -5, serviceClass: ordinary);
      expect(estimate.occupied, 0);
    });
  });

  group('crowd bands', () {
    test('are ordered by load factor', () {
      expect(CrowdLevel.fromLoadFactor(0.1), CrowdLevel.empty);
      expect(CrowdLevel.fromLoadFactor(0.4), CrowdLevel.light);
      expect(CrowdLevel.fromLoadFactor(0.7), CrowdLevel.moderate);
      expect(CrowdLevel.fromLoadFactor(0.95), CrowdLevel.full);
      expect(CrowdLevel.fromLoadFactor(1.2), CrowdLevel.crushed);
    });

    test('report whether a seat is likely', () {
      expect(CrowdLevel.empty.hasSeats, isTrue);
      expect(CrowdLevel.moderate.hasSeats, isTrue);
      expect(CrowdLevel.full.hasSeats, isFalse);
      expect(CrowdLevel.crushed.hasSeats, isFalse);
    });
  });

  group('modelled occupancy', () {
    test('is marked as modelled, not reported', () {
      final estimate = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 9, 0));
      expect(estimate.isReported, isFalse);
      expect(estimate.description, contains('typical demand'));
    });

    test('peak hours are busier than midday', () {
      final peak = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 8, 30));
      final midday = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 13, 0));
      expect(peak.loadFactor, greaterThan(midday.loadFactor));
    });

    test('overnight is the quietest', () {
      final night = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 2, 0));
      final day = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 13, 0));
      expect(night.loadFactor, lessThan(day.loadFactor));
    });

    test('a weekday commuter run is busier than a Sunday one', () {
      final thursday = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 3, 9, 0));
      final sunday = OccupancyEngine.model(
          serviceClass: ordinary, at: DateTime(2026, 9, 6, 9, 0));
      expect(thursday.loadFactor, greaterThan(sunday.loadFactor));
    });

    test('a pilgrimage corridor inverts the weekday pattern', () {
      final weekday = OccupancyEngine.model(
          serviceClass: ordinary,
          at: DateTime(2026, 9, 3, 9, 0),
          isPilgrimageRoute: true);
      final weekend = OccupancyEngine.model(
          serviceClass: ordinary,
          at: DateTime(2026, 9, 6, 9, 0),
          isPilgrimageRoute: true);
      expect(weekend.loadFactor, greaterThan(weekday.loadFactor));
    });

    test('a bus empties as it approaches the destination', () {
      final early = OccupancyEngine.model(
          serviceClass: ordinary,
          at: DateTime(2026, 9, 3, 9, 0),
          journeyFraction: 0.3);
      final late = OccupancyEngine.model(
          serviceClass: ordinary,
          at: DateTime(2026, 9, 3, 9, 0),
          journeyFraction: 0.95);
      expect(late.loadFactor, lessThan(early.loadFactor));
    });

    test('a reserved premium service is never oversold', () {
      for (final hour in [8, 9, 18, 19]) {
        final estimate = OccupancyEngine.model(
            serviceClass: shivneri, at: DateTime(2026, 9, 3, hour, 0));
        expect(estimate.loadFactor, lessThanOrEqualTo(1.0),
            reason: 'a reserved Shivneri cannot exceed capacity');
      }
    });

    test('an ordinary service can carry standees', () {
      final estimate = OccupancyEngine.model(
          serviceClass: ordinary,
          at: DateTime(2026, 9, 3, 8, 30),
          journeyFraction: 0.3);
      expect(estimate.loadFactor, greaterThan(0.8));
    });

    test('the load factor is always in a sane range', () {
      for (var hour = 0; hour < 24; hour++) {
        for (final cls in ServiceClassCatalog.all) {
          for (final fraction in [0.0, 0.3, 0.7, 1.0]) {
            final estimate = OccupancyEngine.model(
              serviceClass: cls,
              at: DateTime(2026, 9, 3, hour, 0),
              journeyFraction: fraction,
            );
            expect(estimate.loadFactor, inInclusiveRange(0.05, 1.25));
            expect(estimate.occupied, greaterThanOrEqualTo(0));
          }
        }
      }
    });
  });

  group('pilgrimage corridor detection', () {
    test('identifies the major shrines', () {
      expect(OccupancyEngine.isPilgrimageCorridor('Pune', 'Shirdi'), isTrue);
      expect(OccupancyEngine.isPilgrimageCorridor('Pandharpur', 'Solapur'),
          isTrue);
      expect(OccupancyEngine.isPilgrimageCorridor('Nashik', 'Trimbakeshwar'),
          isTrue);
    });

    test('is case insensitive', () {
      expect(OccupancyEngine.isPilgrimageCorridor('pune', 'SHIRDI'), isTrue);
    });

    test('an ordinary corridor is not flagged', () {
      expect(OccupancyEngine.isPilgrimageCorridor('Pune', 'Mumbai'), isFalse);
    });
  });

  group('cross-engine consistency', () {
    test('a scheduled arrival built from an estimate reads back correctly', () {
      const departure = 6 * 60 + 30;
      final estimate = EtaEngine.estimate(
        distanceKm: 212,
        serviceClass: semiLuxury,
        intermediateStops: 1,
        departureMinuteOfDay: departure,
      );
      final arrival =
          EtaEngine.arrivalMinuteOfDay(departure, estimate.totalMinutes);
      expect(Schedule.forwardGap(departure, arrival), estimate.totalMinutes);
    });

    test('an overnight long-haul is detected as overnight', () {
      const departure = 20 * 60;
      final estimate = EtaEngine.estimate(
        distanceKm: 840,
        serviceClass: ServiceClassCatalog.byKey('Ordinary Sleeper'),
        intermediateStops: 5,
        departureMinuteOfDay: departure,
      );
      expect(
          Schedule.isOvernightJourney(departure, estimate.totalMinutes),
          isTrue);
    });
  });
}
