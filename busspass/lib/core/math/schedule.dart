/// Timetable arithmetic.
///
/// Departure boards are stored as minutes since midnight (0–1439). That is
/// compact and locale-free, but every naive comparison against "now" breaks at
/// midnight: at 23:45 a 00:30 departure looks 1,395 minutes in the *past* when
/// it is really 45 minutes in the future.
///
/// Everything here works on a **cyclic 1440-minute clock** and returns signed
/// offsets relative to now, so a departure board stays correct through the
/// rollover. That is not a cosmetic detail for MSRTC — long-haul services
/// legitimately depart between 23:00 and 02:00.
library;

import 'dart:math' as math;

/// Minutes in a day.
const int kMinutesPerDay = 1440;

/// A scheduled departure, resolved against a concrete reference time.
class Departure {
  /// Minutes since midnight of the departure, 0–1439.
  final int minuteOfDay;

  /// Whole minutes from the reference time until this departure. Always >= 0;
  /// a departure whose clock time has passed today resolves to tomorrow.
  final int minutesUntil;

  /// The absolute date-time this departure resolves to.
  final DateTime at;

  /// True when [at] falls on the day after the reference time.
  final bool isTomorrow;

  const Departure({
    required this.minuteOfDay,
    required this.minutesUntil,
    required this.at,
    required this.isTomorrow,
  });

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  /// True when boarding is imminent (within 30 minutes).
  bool get isImminent => minutesUntil <= 30;

  @override
  String toString() => 'Departure(${Schedule.formatClock(minuteOfDay)}, '
      'in ${Schedule.formatDuration(minutesUntil)})';
}

/// How a route's departures relate to the current time.
class ServiceStatus {
  /// The next departure, or `null` when the service has no departures at all.
  final Departure? next;

  /// Upcoming departures in chronological order, wrapping into tomorrow.
  final List<Departure> upcoming;

  /// Departures already gone today, most recent first.
  final List<Departure> passed;

  /// Total departures per day.
  final int dailyFrequency;

  /// Mean gap between consecutive departures within the service window, in
  /// minutes. `null` when there are fewer than two departures.
  final int? averageHeadwayMinutes;

  /// First and last departure of the service day.
  final int? firstDepartureMinute;
  final int? lastDepartureMinute;

  const ServiceStatus({
    required this.next,
    required this.upcoming,
    required this.passed,
    required this.dailyFrequency,
    required this.averageHeadwayMinutes,
    required this.firstDepartureMinute,
    required this.lastDepartureMinute,
  });

  bool get hasService => dailyFrequency > 0;

  /// True when the last bus of the day has gone and the next is tomorrow.
  bool get isOvernightGap => next != null && next!.isTomorrow;
}

class Schedule {
  Schedule._();

  /// Minutes since midnight for [time].
  static int minuteOfDay(DateTime time) => time.hour * 60 + time.minute;

  /// Normalise any integer onto 0–1439, handling negatives correctly.
  ///
  /// Dart's `%` already returns a non-negative result for a positive divisor,
  /// but the explicit form documents the intent and survives a refactor to
  /// `remainder()`.
  static int wrap(int minutes) {
    final m = minutes % kMinutesPerDay;
    return m < 0 ? m + kMinutesPerDay : m;
  }

  /// Forward distance from [from] to [to] on the cyclic clock, 0–1439.
  ///
  /// This is the primitive that fixes midnight: `forwardGap(1425, 30) == 45`.
  static int forwardGap(int from, int to) => wrap(to - from);

  /// Signed shortest offset from [from] to [to], in the range -720…720.
  ///
  /// Positive means [to] is ahead. Use this when "12 minutes late" and
  /// "12 minutes early" must be distinguishable.
  static int signedGap(int from, int to) {
    final forward = forwardGap(from, to);
    return forward <= kMinutesPerDay ~/ 2 ? forward : forward - kMinutesPerDay;
  }

  /// Resolve a minute-of-day to the next absolute occurrence at or after [now].
  static Departure resolve(int minuteOfDayValue, DateTime now) {
    final normalised = wrap(minuteOfDayValue);
    final nowMinutes = minuteOfDay(now);
    final gap = forwardGap(nowMinutes, normalised);

    // Same-minute departures count as "now", not 24 hours away.
    final midnight = DateTime(now.year, now.month, now.day);
    final at = midnight.add(Duration(minutes: nowMinutes + gap));

    return Departure(
      minuteOfDay: normalised,
      minutesUntil: gap,
      at: at,
      isTomorrow: nowMinutes + gap >= kMinutesPerDay,
    );
  }

  /// Build a full [ServiceStatus] from a raw departure list.
  ///
  /// [departures] may be unsorted and may contain duplicates; both are handled.
  /// [horizonMinutes] bounds how far ahead `upcoming` looks — the default of one
  /// full day means every departure appears exactly once.
  static ServiceStatus statusFor(
    List<int> departures,
    DateTime now, {
    int horizonMinutes = kMinutesPerDay,
    int maxUpcoming = 100,
    int maxPassed = 100,
  }) {
    if (departures.isEmpty) {
      return const ServiceStatus(
        next: null,
        upcoming: [],
        passed: [],
        dailyFrequency: 0,
        averageHeadwayMinutes: null,
        firstDepartureMinute: null,
        lastDepartureMinute: null,
      );
    }

    final unique = departures.map(wrap).toSet().toList()..sort();
    final nowMinutes = minuteOfDay(now);

    final resolved = unique.map((m) => resolve(m, now)).toList()
      ..sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));

    final upcoming = resolved
        .where((d) => d.minutesUntil <= horizonMinutes)
        .take(maxUpcoming)
        .toList();

    // "Passed" means earlier today on the wall clock, most recent first.
    final passed = unique
        .where((m) => m < nowMinutes)
        .map((m) {
          final midnight = DateTime(now.year, now.month, now.day);
          return Departure(
            minuteOfDay: m,
            minutesUntil: 0,
            at: midnight.add(Duration(minutes: m)),
            isTomorrow: false,
          );
        })
        .toList()
      ..sort((a, b) => b.minuteOfDay.compareTo(a.minuteOfDay));

    return ServiceStatus(
      next: upcoming.isEmpty ? resolved.first : upcoming.first,
      upcoming: upcoming,
      passed: passed.take(maxPassed).toList(),
      dailyFrequency: unique.length,
      averageHeadwayMinutes: _averageHeadway(unique),
      firstDepartureMinute: unique.first,
      lastDepartureMinute: unique.last,
    );
  }

  /// Mean gap between consecutive departures, measured across the service
  /// window only.
  ///
  /// The overnight gap is deliberately excluded: including it on a service that
  /// runs 06:00–22:00 would report a 3-hour "average headway" for a bus that
  /// actually comes every 30 minutes.
  static int? _averageHeadway(List<int> sorted) {
    if (sorted.length < 2) return null;
    final span = sorted.last - sorted.first;
    return (span / (sorted.length - 1)).round();
  }

  /// The next departure at or after [now], or `null` when the list is empty.
  static Departure? nextDeparture(List<int> departures, DateTime now) {
    if (departures.isEmpty) return null;
    return statusFor(departures, now).next;
  }

  /// The next departure that leaves at least [bufferMinutes} from now.
  ///
  /// This is the connection-safety primitive: after arriving at a transfer stop,
  /// a rider cannot board a bus leaving in two minutes at the other end of the
  /// stand.
  static Departure? nextDepartureAfter(
    List<int> departures,
    DateTime now, {
    int bufferMinutes = 0,
  }) {
    if (departures.isEmpty) return null;
    final threshold = now.add(Duration(minutes: bufferMinutes));
    final status = statusFor(departures, threshold);
    final next = status.next;
    if (next == null) return null;
    // Re-resolve against the real `now` so `minutesUntil` is what the rider
    // actually waits, inclusive of the buffer.
    return resolve(next.minuteOfDay, now);
  }

  /// `HH:MM` in 24-hour form.
  static String formatClock24(int minuteOfDayValue) {
    final m = wrap(minuteOfDayValue);
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final min = (m % 60).toString().padLeft(2, '0');
    return '$h:$min';
  }

  /// `h:MM AM/PM`, the form Indian riders read on printed boards.
  static String formatClock(int minuteOfDayValue) {
    final m = wrap(minuteOfDayValue);
    final hour24 = m ~/ 60;
    final minute = m % 60;
    final period = hour24 < 12 ? 'AM' : 'PM';
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Compact duration: `45m`, `2h 15m`, `1d 3h`.
  static String formatDuration(int minutes) {
    if (minutes <= 0) return 'now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours < 24) {
      return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
    }
    final days = hours ~/ 24;
    final remHours = hours % 24;
    return remHours == 0 ? '${days}d' : '${days}d ${remHours}h';
  }

  /// Relative phrasing for a countdown: `Boarding now`, `in 12 min`,
  /// `in 2h 40m`, `Tomorrow 05:30`.
  static String formatRelative(Departure departure) {
    if (departure.minutesUntil <= 1) return 'Boarding now';
    if (departure.isTomorrow && departure.minutesUntil > 240) {
      return 'Tomorrow ${formatClock(departure.minuteOfDay)}';
    }
    return 'in ${formatDuration(departure.minutesUntil)}';
  }

  /// Part of day, used for greetings and for period-aware timetable grouping.
  static DayPart dayPart(int minuteOfDayValue) {
    final m = wrap(minuteOfDayValue);
    if (m < 5 * 60) return DayPart.night;
    if (m < 12 * 60) return DayPart.morning;
    if (m < 16 * 60) return DayPart.afternoon;
    if (m < 20 * 60) return DayPart.evening;
    return DayPart.night;
  }

  /// Add [minutes] to a minute-of-day, wrapping across midnight.
  static int addMinutes(int minuteOfDayValue, int minutes) =>
      wrap(minuteOfDayValue + minutes);

  /// Whether [minuteOfDayValue] falls inside the window `[start, end)`,
  /// correctly handling windows that span midnight (e.g. 22:00–04:00).
  static bool isWithinWindow(int minuteOfDayValue, int start, int end) {
    final m = wrap(minuteOfDayValue);
    final s = wrap(start);
    final e = wrap(end);
    if (s == e) return true; // full day
    if (s < e) return m >= s && m < e;
    return m >= s || m < e; // wraps midnight
  }

  /// Whether a journey of [durationMinutes] departing at [departureMinute]
  /// overlaps the 22:00–06:00 window enough to count as overnight travel.
  ///
  /// Used to surface sleeper services and night-halt warnings.
  static bool isOvernightJourney(int departureMinute, int durationMinutes) {
    if (durationMinutes >= 6 * 60) {
      // Long enough that any evening start lands in the night window.
      if (isWithinWindow(departureMinute, 18 * 60, 6 * 60)) return true;
    }
    final arrival = addMinutes(departureMinute, durationMinutes);
    // Count the trip as overnight if it starts before and ends after midnight.
    return departureMinute > arrival && durationMinutes < kMinutesPerDay;
  }

  /// Clamp a duration into a sane range so a corrupt data point cannot render
  /// an absurd ETA.
  static int sanitiseDuration(int minutes) =>
      math.max(1, math.min(minutes, 3 * kMinutesPerDay));
}

/// Coarse time-of-day bucket.
enum DayPart {
  morning('Good morning'),
  afternoon('Good afternoon'),
  evening('Good evening'),
  night('Good evening');

  const DayPart(this.greeting);
  final String greeting;
}
