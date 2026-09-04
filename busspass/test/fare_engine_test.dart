import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/data/models/network_models.dart';

void main() {
  ServiceClass cls(String key) => ServiceClassCatalog.byKey(key);

  group('stage counting', () {
    test('any distance above zero costs at least one stage', () {
      expect(FareEngine.stagesFor(0.1), 1);
      expect(FareEngine.stagesFor(1), 1);
      expect(FareEngine.stagesFor(5.9), 1);
    });

    test('an exact stage boundary does not roll into the next stage', () {
      expect(FareEngine.stagesFor(6), 1);
      expect(FareEngine.stagesFor(12), 2);
      expect(FareEngine.stagesFor(60), 10);
    });

    test('a partial stage is charged whole', () {
      expect(FareEngine.stagesFor(6.1), 2);
      expect(FareEngine.stagesFor(11.9), 2);
      expect(FareEngine.stagesFor(12.1), 3);
    });

    test('zero and negative distance cost nothing', () {
      expect(FareEngine.stagesFor(0), 0);
      expect(FareEngine.stagesFor(-5), 0);
    });
  });

  group('rounding to ₹5', () {
    test('rounds to the nearest multiple of five', () {
      expect(FareEngine.roundFare(11.40), 10);
      expect(FareEngine.roundFare(13.65), 15);
      expect(FareEngine.roundFare(22.80), 25);
      expect(FareEngine.roundFare(17.49), 15);
    });

    test('halves round upward, matching conductor practice', () {
      expect(FareEngine.roundFare(12.5), 15);
      expect(FareEngine.roundFare(17.5), 20);
    });

    test('every fare is tenderable in ₹5 notes and coins', () {
      for (var km = 1.0; km <= 900; km += 3.7) {
        for (final key in FareEngine.tariff.keys) {
          final fare = FareEngine.baseFare(km, key);
          expect(fare % 5, 0,
              reason: '₹$fare for ${km.toStringAsFixed(1)} km on $key '
                  'is not a multiple of 5');
        }
      }
    });
  });

  group('base fare', () {
    test('honours the ₹10 minimum', () {
      // One Ordinary stage is ₹11.40, which rounds to ₹10 — exactly the floor.
      expect(FareEngine.baseFare(1, 'Ordinary'), 10);
      expect(FareEngine.baseFare(6, 'Ordinary'), 10);
    });

    test('matches the published tariff on a known corridor', () {
      // Mumbai–Pune, 150 km = 25 stages.
      // Ordinary  25 × 11.40 = 285.00 → ₹285
      // Shivneri  25 × 21.25 = 531.25 → ₹530
      expect(FareEngine.baseFare(150, 'Ordinary'), 285);
      expect(FareEngine.baseFare(150, 'Shivneri'), 530);
      expect(FareEngine.baseFare(150, 'Semi Luxury'), 340); // 341.25 → 340
      expect(FareEngine.baseFare(150, 'Shivshahi'), 355);   // 355.00
    });

    test('is monotonic in distance', () {
      var previous = 0;
      for (var km = 1.0; km <= 800; km += 6) {
        final fare = FareEngine.baseFare(km, 'Ordinary');
        expect(fare, greaterThanOrEqualTo(previous));
        previous = fare;
      }
    });

    test('is monotonic in service tier at the same distance', () {
      const km = 240.0;
      expect(FareEngine.baseFare(km, 'Ordinary'),
          lessThan(FareEngine.baseFare(km, 'Semi Luxury')));
      expect(FareEngine.baseFare(km, 'Semi Luxury'),
          lessThan(FareEngine.baseFare(km, 'Shivshahi')));
      expect(FareEngine.baseFare(km, 'Shivshahi'),
          lessThan(FareEngine.baseFare(km, 'Shivneri')));
      expect(FareEngine.baseFare(km, 'Shivneri'),
          lessThan(FareEngine.baseFare(km, 'Shivneri Sleeper')));
    });

    test('a short hop costs proportionally less than the full corridor', () {
      // The bug this guards: charging full-route fare for a Panvel–Lonavala hop.
      final fullRoute = FareEngine.baseFare(150, 'Shivneri');
      final shortHop = FareEngine.baseFare(42, 'Shivneri');
      expect(shortHop, lessThan(fullRoute ~/ 3));
    });
  });

  group('stage pricing is a step function', () {
    test('distances within one stage cost the same', () {
      final a = FareEngine.baseFare(13, 'Ordinary');
      final b = FareEngine.baseFare(17, 'Ordinary');
      final c = FareEngine.baseFare(18, 'Ordinary');
      expect(a, b, reason: '13 km and 17 km are both 3 stages');
      expect(b, c, reason: '18 km is still exactly 3 stages');
      expect(FareEngine.baseFare(18.5, 'Ordinary'), greaterThan(c));
    });

    test('reports the unused kilometres in the last stage', () {
      final f = FareEngine.compute(
        distanceKm: 13,
        serviceClass: cls('Ordinary'),
      );
      expect(f.stages, 3);
      expect(f.unusedStageKm, closeTo(5.0, 1e-9)); // 18 km bought, 13 travelled
    });

    test('an exact multiple of six wastes nothing', () {
      final f = FareEngine.compute(
        distanceKm: 18,
        serviceClass: cls('Ordinary'),
      );
      expect(f.unusedStageKm, closeTo(0, 1e-9));
    });

    test('reports the next stage boundary', () {
      expect(FareEngine.nextStageBoundaryKm(13), 18);
      expect(FareEngine.nextStageBoundaryKm(18), 18);
      expect(FareEngine.nextStageBoundaryKm(18.5), 24);
    });
  });

  group('concessions', () {
    test('an adult pays the base fare', () {
      final f = FareEngine.compute(
        distanceKm: 150,
        serviceClass: cls('Ordinary'),
      );
      expect(f.total, 285);
      expect(f.concession, 0);
    });

    test('a child pays half, re-rounded to ₹5', () {
      final f = FareEngine.compute(
        distanceKm: 150,
        serviceClass: cls('Ordinary'),
        category: RiderCategory.child,
      );
      // 285 / 2 = 142.5 → ₹145 after ₹5 rounding.
      expect(f.total, 145);
      expect(f.concession, 140);
    });

    test('a senior citizen travels free under Amrut Jyeshtha Nagarik', () {
      final f = FareEngine.compute(
        distanceKm: 430,
        serviceClass: cls('Shivneri'),
        category: RiderCategory.seniorCitizen,
      );
      expect(f.total, 0);
      expect(f.baseFare, greaterThan(0));
      expect(f.concession, f.baseFare);
    });

    test('a full concession is not dragged back up to the ₹10 floor', () {
      final f = FareEngine.compute(
        distanceKm: 5,
        serviceClass: cls('Ordinary'),
        category: RiderCategory.freedomFighter,
      );
      expect(f.total, 0);
    });

    test('a half concession still respects the ₹10 floor', () {
      final f = FareEngine.compute(
        distanceKm: 5,
        serviceClass: cls('Ordinary'),
        category: RiderCategory.woman,
      );
      // Base is ₹10; half would be ₹5, but no ticket is issued below ₹10.
      expect(f.total, 10);
    });

    test('every concession category produces a tenderable amount', () {
      for (final category in RiderCategory.values) {
        final f = FareEngine.compute(
          distanceKm: 212,
          serviceClass: cls('Semi Luxury'),
          category: category,
        );
        expect(f.total % 5, 0, reason: '${category.name} produced ₹${f.total}');
        expect(f.total, lessThanOrEqualTo(f.baseFare));
      }
    });
  });

  group('surcharges', () {
    test('reservation and luggage fees are added after the concession', () {
      final f = FareEngine.compute(
        distanceKm: 150,
        serviceClass: cls('Ordinary'),
        category: RiderCategory.child,
        reservationFee: 20,
        luggageFee: 15,
      );
      // Concession applies to the ₹285 passenger fare only: 145 + 20 + 15.
      expect(f.total, 180);
    });

    test('a free rider still pays surcharges', () {
      final f = FareEngine.compute(
        distanceKm: 150,
        serviceClass: cls('Ordinary'),
        category: RiderCategory.seniorCitizen,
        reservationFee: 20,
      );
      expect(f.total, 20);
    });
  });

  group('breakdown arithmetic', () {
    test('components reconcile to the total', () {
      final f = FareEngine.compute(
        distanceKm: 376,
        serviceClass: cls('Shivshahi'),
        category: RiderCategory.student,
        reservationFee: 25,
        luggageFee: 10,
      );
      expect(f.baseFare - f.concession + f.reservationFee + f.luggageFee,
          f.total);
    });

    test('raw fare is stages times the tariff', () {
      final f = FareEngine.compute(
        distanceKm: 100,
        serviceClass: cls('Shivneri'),
      );
      expect(f.stages, 17); // ceil(100 / 6)
      expect(f.rawFare, closeTo(17 * 21.25, 1e-9));
      expect(f.baseFare, 360); // 361.25 → 360
    });

    test('per-km cost falls as distance rises within a tier', () {
      final short = FareEngine.compute(
        distanceKm: 20,
        serviceClass: cls('Ordinary'),
      );
      final long = FareEngine.compute(
        distanceKm: 400,
        serviceClass: cls('Ordinary'),
      );
      expect(short.perKm, greaterThan(long.perKm));
    });
  });

  group('service class resolution', () {
    test('canonical keys pass through', () {
      for (final key in FareEngine.tariff.keys) {
        expect(FareEngine.canonicalKey(key), key);
      }
    });

    test('scraped Marathi-derived labels resolve', () {
      expect(FareEngine.canonicalKey('Lalpari'), 'Ordinary');
      expect(FareEngine.canonicalKey('Hirkani'), 'Semi Luxury');
      expect(FareEngine.canonicalKey('Ashiad'), 'Semi Luxury');
      expect(FareEngine.canonicalKey('Shayanyan'), 'Ordinary Sleeper');
      expect(FareEngine.canonicalKey('E-Shivneri'), 'Shivneri');
    });

    test('sleeper variants are not swallowed by the seater branch', () {
      // The ordering bug this guards: 'Shivneri Sleeper' matching 'shivneri'
      // first and losing the sleeper tariff.
      expect(FareEngine.canonicalKey('shivneri sleeper'), 'Shivneri Sleeper');
      expect(FareEngine.canonicalKey('Shivshahi Sleeping'), 'Shivshahi Sleeper');
      expect(FareEngine.canonicalKey('AC Sleeper Shivneri'), 'Shivneri Sleeper');
    });

    test('case and whitespace are tolerated', () {
      expect(FareEngine.canonicalKey('  semi luxury  '), 'Semi Luxury');
      expect(FareEngine.canonicalKey('SHIVSHAHI'), 'Shivshahi');
    });

    test('an unknown label falls back to Ordinary rather than throwing', () {
      expect(FareEngine.canonicalKey('Kilometre'), 'Ordinary');
      expect(FareEngine.canonicalKey(''), 'Ordinary');
      expect(FareEngine.canonicalKey('Vithai'), 'Ordinary');
    });
  });

  group('fare ladder', () {
    test('is ordered cheapest first', () {
      final ladder = FareEngine.fareLadder(212, ServiceClassCatalog.all);
      expect(ladder, isNotEmpty);
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i].fare, greaterThanOrEqualTo(ladder[i - 1].fare));
      }
      expect(ladder.first.serviceClass.key, 'Ordinary');
    });
  });

  group('comfort summary', () {
    test('describes AC and berths from class properties, not the name', () {
      expect(cls('Shivneri Sleeper').comfortSummary,
          contains('Air-conditioned'));
      expect(cls('Shivneri Sleeper').comfortSummary, contains('Berths'));
      expect(cls('Ordinary').comfortSummary, contains('Non-AC'));
      expect(cls('Ordinary').comfortSummary, contains('Seater'));
      expect(cls('Ordinary').comfortSummary, contains('every stop'));
    });
  });

  group('rupee formatting', () {
    test('uses Indian digit grouping', () {
      expect(FareEngine.formatRupees(0), '₹0');
      expect(FareEngine.formatRupees(285), '₹285');
      expect(FareEngine.formatRupees(1250), '₹1,250');
      expect(FareEngine.formatRupees(123456), '₹1,23,456');
    });
  });
}
