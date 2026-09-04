/// MSRTC fare computation.
///
/// Maharashtra State Road Transport Corporation prices by **stage**, not by
/// kilometre: the route is divided into 6 km blocks and any part of a block is
/// charged as a whole block. Each service class has its own per-stage tariff.
/// The result is rounded to the nearest ₹5, with a ₹10 floor.
///
/// Tariffs below are the 18-Jul-2026 revision (13.56% hike, STA approved).
///
/// The consequence of stage pricing that the UI has to communicate: fare is a
/// **step function**, not a line. A 12 km trip and a 17 km trip both cost three
/// stages. Riders who understand this stop feeling overcharged on short hops.
library;

import 'dart:math' as math;

/// Whether a service is air-conditioned, and whether it has berths. Drives both
/// pricing and the ETA speed model.
class ServiceClass {
  /// Stable key used in data files and fare lookups, e.g. `Shivneri Sleeper`.
  final String key;

  /// Display name, e.g. `Shivneri AC Sleeper`.
  final String label;

  /// Devanagari name, for Marathi and Hindi locales.
  final String marathi;

  /// Rupees per 6 km stage.
  final double stageRate;

  final bool ac;
  final bool sleeper;

  /// 1 = Ordinary … 4 = Shivneri. Higher tiers stop less and run faster.
  final int tier;

  /// Free-running speed on open highway, km/h.
  final double cruiseKmph;

  /// Average halt duration at an intermediate stop, minutes.
  final double dwellMin;

  /// Fraction of intermediate stops this class actually serves. An Ordinary
  /// bus halts everywhere (1.0); a Shivneri skips 80% of them (0.2).
  final double stopDensity;

  /// Seated (or berth) capacity, used for occupancy percentages.
  final int seats;

  const ServiceClass({
    required this.key,
    required this.label,
    required this.marathi,
    required this.stageRate,
    required this.ac,
    required this.sleeper,
    required this.tier,
    required this.cruiseKmph,
    required this.dwellMin,
    required this.stopDensity,
    required this.seats,
  });

  factory ServiceClass.fromJson(Map<String, dynamic> json) => ServiceClass(
        key: json['key'] as String,
        label: json['label'] as String? ?? json['key'] as String,
        marathi: json['marathi'] as String? ?? '',
        stageRate: (json['stageRate'] as num?)?.toDouble() ?? 11.40,
        ac: json['ac'] as bool? ?? false,
        sleeper: json['sleeper'] as bool? ?? false,
        tier: (json['tier'] as num?)?.toInt() ?? 1,
        cruiseKmph: (json['cruiseKmph'] as num?)?.toDouble() ?? 46,
        dwellMin: (json['dwellMin'] as num?)?.toDouble() ?? 2,
        stopDensity: (json['stopDensity'] as num?)?.toDouble() ?? 1,
        seats: (json['seats'] as num?)?.toInt() ?? 52,
      );

  /// One-line summary of what the rider actually gets, derived from the class
  /// properties rather than guessed from substring matching on the name.
  String get comfortSummary {
    final parts = <String>[
      if (ac) 'Air-conditioned' else 'Non-AC',
      if (sleeper) 'Berths' else 'Seater',
    ];
    parts.add(switch (tier) {
      >= 4 => 'expressway, minimal halts',
      3 => 'limited halts',
      2 => 'moderate halts',
      _ => 'halts at every stop',
    });
    return parts.join(' · ');
  }
}

/// Rider categories eligible for statutory MSRTC concessions.
///
/// Percentages are the corporation's published concessions. Concessions apply
/// to the computed stage fare, and the ₹5 rounding is re-applied afterwards so
/// the discounted amount is still tenderable in cash.
enum RiderCategory {
  /// No concession.
  adult('Adult', 0),

  /// Children 5–12 years travel at half fare. Under 5 travel free.
  child('Child (5–12 yrs)', 50),

  /// Amrut Jyeshtha Nagarik Yojana — 65+ travel free on MSRTC.
  seniorCitizen('Senior citizen (65+)', 100),

  /// Mahila Samman Yojana — 50% concession for women.
  woman('Woman (Mahila Samman)', 50),

  /// Student monthly/quarterly concession pass rate.
  student('Student', 50),

  /// Persons with disability travel free with an escort at half fare.
  disability('Person with disability', 100),

  /// Freedom fighters travel free.
  freedomFighter('Freedom fighter', 100);

  const RiderCategory(this.label, this.discountPercent);

  final String label;
  final int discountPercent;

  bool get isFree => discountPercent >= 100;
}

/// A fully itemised fare, so the UI can show the rider exactly how the number
/// was reached instead of a bare total.
class FareBreakdown {
  /// Chargeable distance in kilometres.
  final double distanceKm;

  /// Number of 6 km stages charged (`ceil(distanceKm / 6)`).
  final int stages;

  /// Tariff per stage for the chosen service class.
  final double stageRate;

  /// `stages * stageRate`, before rounding and before concession.
  final double rawFare;

  /// Base fare after ₹5 rounding and the ₹10 floor. What an adult pays.
  final int baseFare;

  /// Rider category the fare was computed for.
  final RiderCategory category;

  /// Rupees removed by the concession.
  final int concession;

  /// Reservation / booking surcharge, if any.
  final int reservationFee;

  /// Luggage surcharge, if any.
  final int luggageFee;

  /// Final amount payable.
  final int total;

  /// Service class used.
  final ServiceClass serviceClass;

  const FareBreakdown({
    required this.distanceKm,
    required this.stages,
    required this.stageRate,
    required this.rawFare,
    required this.baseFare,
    required this.category,
    required this.concession,
    required this.reservationFee,
    required this.luggageFee,
    required this.total,
    required this.serviceClass,
  });

  /// Effective cost per kilometre. Useful for comparing a short hop against a
  /// long haul, where stage rounding distorts the headline number.
  double get perKm => distanceKm <= 0 ? 0 : total / distanceKm;

  /// Kilometres bought but not travelled, because the last stage is partial.
  /// Non-zero whenever `distanceKm` is not an exact multiple of 6.
  double get unusedStageKm =>
      math.max(0, stages * FareEngine.stageKm - distanceKm);

  @override
  String toString() =>
      'FareBreakdown(${distanceKm.toStringAsFixed(1)} km, $stages stages, '
      '${serviceClass.key}, ₹$total)';
}

class FareEngine {
  FareEngine._();

  /// One MSRTC stage, in kilometres.
  static const double stageKm = 6.0;

  /// Fares are tendered in ₹5 increments.
  static const int roundToNearest = 5;

  /// No ticket is issued below this amount.
  static const int minimumFare = 10;

  /// Effective date of the tariff table in [tariff].
  static const String tariffRevision = '18 Jul 2026';

  /// Per-stage tariff by service class key (₹ per 6 km).
  static const Map<String, double> tariff = {
    'Ordinary': 11.40,
    'Semi Luxury': 13.65,
    'Sleeper Seater': 15.50,
    'Ordinary Sleeper': 16.75,
    'Shivshahi': 14.20,
    'Shivshahi Sleeper': 15.35,
    'Shivneri': 21.25,
    'Shivneri Sleeper': 25.35,
  };

  /// Legacy / scraped labels folded onto canonical keys.
  static const Map<String, String> _aliases = {
    'Sleeper': 'Ordinary Sleeper',
    'Shayanyan': 'Ordinary Sleeper',
    'Lalpari': 'Ordinary',
    'Hirkani': 'Semi Luxury',
    'Ashiad': 'Semi Luxury',
    'Asiad': 'Semi Luxury',
    'E-Shivneri': 'Shivneri',
    'E-Shivai': 'Ordinary',
    'Shivai': 'Ordinary',
    'Vithai': 'Ordinary',
    'E-Bus': 'Ordinary',
  };

  /// Resolve any label to a canonical service class key, falling back to
  /// `Ordinary` for anything unrecognised.
  static String canonicalKey(String raw) {
    final trimmed = raw.trim();
    if (tariff.containsKey(trimmed)) return trimmed;
    if (_aliases.containsKey(trimmed)) return _aliases[trimmed]!;

    final lower = trimmed.toLowerCase();
    for (final entry in tariff.keys) {
      if (entry.toLowerCase() == lower) return entry;
    }
    for (final entry in _aliases.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    // Heuristic last resort, ordered most specific first so
    // "Shivneri Sleeper" is not swallowed by the "Shivneri" branch.
    if (lower.contains('shivneri')) {
      return lower.contains('sleep') ? 'Shivneri Sleeper' : 'Shivneri';
    }
    if (lower.contains('shivshahi')) {
      return lower.contains('sleep') ? 'Shivshahi Sleeper' : 'Shivshahi';
    }
    if (lower.contains('sleeper') && lower.contains('seat')) {
      return 'Sleeper Seater';
    }
    if (lower.contains('sleep') || lower.contains('shayan')) {
      return 'Ordinary Sleeper';
    }
    if (lower.contains('semi') || lower.contains('luxur')) return 'Semi Luxury';
    return 'Ordinary';
  }

  /// Stage tariff for [serviceClassKey], in rupees.
  static double stageRateFor(String serviceClassKey) =>
      tariff[canonicalKey(serviceClassKey)] ?? tariff['Ordinary']!;

  /// Number of stages charged for [km].
  ///
  /// Any distance above zero costs at least one stage — a 1 km hop is a full
  /// stage, which is exactly why the app shows `unusedStageKm`.
  static int stagesFor(double km) {
    if (km <= 0) return 0;
    return (km / stageKm).ceil();
  }

  /// Round to the nearest ₹5, halves upward (matching conductor practice).
  static int roundFare(double amount) {
    if (amount <= 0) return 0;
    return ((amount / roundToNearest).round()) * roundToNearest;
  }

  /// Adult base fare for [km] on [serviceClassKey], in whole rupees.
  ///
  /// `fare = max(10, round5(ceil(km / 6) * stageRate))`
  static int baseFare(double km, String serviceClassKey) {
    final stages = stagesFor(km);
    if (stages == 0) return 0;
    final raw = stages * stageRateFor(serviceClassKey);
    return math.max(minimumFare, roundFare(raw));
  }

  /// Full itemised fare.
  ///
  /// [reservationFee] covers advance booking (MSRTC charges a per-seat booking
  /// fee on reserved services); [luggageFee] covers registered luggage. Both
  /// are added after the concession, since concessions apply to the passenger
  /// fare only.
  static FareBreakdown compute({
    required double distanceKm,
    required ServiceClass serviceClass,
    RiderCategory category = RiderCategory.adult,
    int reservationFee = 0,
    int luggageFee = 0,
  }) {
    final stages = stagesFor(distanceKm);
    final rate = serviceClass.stageRate > 0
        ? serviceClass.stageRate
        : stageRateFor(serviceClass.key);
    final raw = stages * rate;
    final base = stages == 0 ? 0 : math.max(minimumFare, roundFare(raw));

    // Concession is computed on the base fare then re-rounded to ₹5 so the
    // discounted fare is still payable in cash. A 100% concession short-circuits
    // to zero rather than rounding up to the ₹10 floor.
    final int discounted;
    if (category.isFree) {
      discounted = 0;
    } else if (category.discountPercent == 0) {
      discounted = base;
    } else {
      final afterDiscount = base * (100 - category.discountPercent) / 100.0;
      discounted = math.max(minimumFare, roundFare(afterDiscount));
    }

    final concession = base - discounted;
    final total = discounted + reservationFee + luggageFee;

    return FareBreakdown(
      distanceKm: distanceKm,
      stages: stages,
      stageRate: rate,
      rawFare: raw,
      baseFare: base,
      category: category,
      concession: concession,
      reservationFee: reservationFee,
      luggageFee: luggageFee,
      total: total,
      serviceClass: serviceClass,
    );
  }

  /// Adult fares for every class in [classes} over [distanceKm], cheapest first.
  static List<({ServiceClass serviceClass, int fare})> fareLadder(
    double distanceKm,
    List<ServiceClass> classes,
  ) {
    final out = classes
        .map((c) => (
              serviceClass: c,
              fare: baseFare(distanceKm, c.key) == 0
                  ? 0
                  : math.max(minimumFare, roundFare(stagesFor(distanceKm) * c.stageRate)),
            ))
        .toList();
    out.sort((a, b) => a.fare.compareTo(b.fare));
    return out;
  }

  /// Distance at which the next stage boundary is crossed.
  ///
  /// Lets the UI tell a rider "3 km further costs the same" — genuinely useful
  /// when choosing between two nearby alighting points.
  static double nextStageBoundaryKm(double km) {
    final stages = stagesFor(km);
    return stages * stageKm;
  }

  /// Format rupees for display with the ₹ sign and thousands separators.
  static String formatRupees(int amount) {
    // Indian grouping: last three digits, then pairs (1,23,456).
    final s = amount.abs().toString();
    if (s.length <= 3) return '₹${amount < 0 ? '-' : ''}$s';

    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '₹${amount < 0 ? '-' : ''}${groups.join(',')},$last3';
  }
}
