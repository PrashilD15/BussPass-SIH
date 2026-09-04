import 'package:flutter_test/flutter_test.dart';

import 'package:busspass/core/math/schedule.dart';

void main() {
  // A fixed reference so nothing depends on the wall clock.
  final at1145pm = DateTime(2026, 9, 3, 23, 45);
  final at9am = DateTime(2026, 9, 3, 9, 0);
  final atNoon = DateTime(2026, 9, 3, 12, 0);

  group('minute-of-day conversion', () {
    test('midnight is zero', () {
      expect(Schedule.minuteOfDay(DateTime(2026, 9, 3, 0, 0)), 0);
    });

    test('the last minute of the day is 1439', () {
      expect(Schedule.minuteOfDay(DateTime(2026, 9, 3, 23, 59)), 1439);
    });

    test('noon is 720', () {
      expect(Schedule.minuteOfDay(atNoon), 720);
    });
  });

  group('cyclic wrapping', () {
    test('values inside the day pass through', () {
      expect(Schedule.wrap(0), 0);
      expect(Schedule.wrap(720), 720);
      expect(Schedule.wrap(1439), 1439);
    });

    test('a full day wraps to zero', () {
      expect(Schedule.wrap(1440), 0);
      expect(Schedule.wrap(2880), 0);
    });

    test('negatives wrap forward, not to a negative', () {
      expect(Schedule.wrap(-1), 1439);
      expect(Schedule.wrap(-60), 1380);
      expect(Schedule.wrap(-1441), 1439);
    });
  });

  group('forward gap across midnight', () {
    test('a later time today is a plain difference', () {
      expect(Schedule.forwardGap(9 * 60, 11 * 60), 120);
    });

    test('an earlier clock time is tomorrow, not negative', () {
      // This is the bug the old code had: at 23:45, a 00:30 departure was
      // treated as 1,395 minutes in the past instead of 45 ahead.
      expect(Schedule.forwardGap(23 * 60 + 45, 30), 45);
    });

    test('the same minute is zero, not a full day', () {
      expect(Schedule.forwardGap(600, 600), 0);
    });

    test('is always in 0–1439', () {
      for (var a = 0; a < 1440; a += 37) {
        for (var b = 0; b < 1440; b += 53) {
          final gap = Schedule.forwardGap(a, b);
          expect(gap, greaterThanOrEqualTo(0));
          expect(gap, lessThan(1440));
        }
      }
    });
  });

  group('signed gap', () {
    test('ahead is positive, behind is negative', () {
      expect(Schedule.signedGap(600, 660), 60);
      expect(Schedule.signedGap(660, 600), -60);
    });

    test('distinguishes late from early across midnight', () {
      // Scheduled 23:50, actual 00:10 → 20 minutes late.
      expect(Schedule.signedGap(23 * 60 + 50, 10), 20);
      // Scheduled 00:10, actual 23:50 → 20 minutes early.
      expect(Schedule.signedGap(10, 23 * 60 + 50), -20);
    });

    test('stays within ±720', () {
      for (var a = 0; a < 1440; a += 41) {
        for (var b = 0; b < 1440; b += 61) {
          final gap = Schedule.signedGap(a, b);
          expect(gap, greaterThanOrEqualTo(-720));
          expect(gap, lessThanOrEqualTo(720));
        }
      }
    });
  });

  group('resolving a departure', () {
    test('a later time today resolves to today', () {
      final d = Schedule.resolve(11 * 60, at9am);
      expect(d.minutesUntil, 120);
      expect(d.isTomorrow, isFalse);
      expect(d.at, DateTime(2026, 9, 3, 11, 0));
    });

    test('an earlier time resolves to tomorrow', () {
      final d = Schedule.resolve(7 * 60, at9am);
      expect(d.minutesUntil, 22 * 60);
      expect(d.isTomorrow, isTrue);
      expect(d.at, DateTime(2026, 9, 4, 7, 0));
    });

    test('a post-midnight departure viewed late at night is imminent', () {
      final d = Schedule.resolve(30, at1145pm);
      expect(d.minutesUntil, 45);
      expect(d.isTomorrow, isTrue);
      expect(d.at, DateTime(2026, 9, 4, 0, 30));
    });

    test('the current minute resolves to now', () {
      final d = Schedule.resolve(9 * 60, at9am);
      expect(d.minutesUntil, 0);
      expect(d.isTomorrow, isFalse);
    });

    test('exposes the clock components', () {
      final d = Schedule.resolve(14 * 60 + 35, at9am);
      expect(d.hour, 14);
      expect(d.minute, 35);
    });

    test('flags an imminent departure', () {
      expect(Schedule.resolve(9 * 60 + 20, at9am).isImminent, isTrue);
      expect(Schedule.resolve(11 * 60, at9am).isImminent, isFalse);
    });
  });

  group('service status', () {
    // A plausible Sangamner board: hourly from 05:00, last at 22:00.
    final hourly = [
      for (var h = 5; h <= 22; h++) h * 60,
    ];

    test('an empty board reports no service', () {
      final status = Schedule.statusFor(const [], at9am);
      expect(status.hasService, isFalse);
      expect(status.next, isNull);
      expect(status.upcoming, isEmpty);
      expect(status.dailyFrequency, 0);
    });

    test('splits upcoming from passed correctly', () {
      final status = Schedule.statusFor(hourly, at9am);
      // 05:00–08:00 have gone; 09:00 onward remain.
      expect(status.passed.length, 4);
      expect(status.passed.first.minuteOfDay, 8 * 60);
      expect(status.next!.minuteOfDay, 9 * 60);
    });

    test('upcoming is ordered by how soon it departs, wrapping midnight', () {
      final status = Schedule.statusFor(hourly, at1145pm);
      // Every departure has gone today, so the first is tomorrow's 05:00.
      expect(status.next!.minuteOfDay, 5 * 60);
      expect(status.next!.isTomorrow, isTrue);
      expect(status.isOvernightGap, isTrue);

      for (var i = 1; i < status.upcoming.length; i++) {
        expect(status.upcoming[i].minutesUntil,
            greaterThanOrEqualTo(status.upcoming[i - 1].minutesUntil));
      }
    });

    test('deduplicates and sorts a messy board', () {
      final messy = [600, 540, 600, 480, 540];
      final status = Schedule.statusFor(messy, at9am);
      expect(status.dailyFrequency, 3);
      expect(status.firstDepartureMinute, 480);
      expect(status.lastDepartureMinute, 600);
    });

    test('every departure appears exactly once within a day horizon', () {
      final status = Schedule.statusFor(hourly, atNoon);
      expect(status.upcoming.length, hourly.length);
    });

    test('headway excludes the overnight gap', () {
      final status = Schedule.statusFor(hourly, at9am);
      // 05:00–22:00 hourly is a 60-minute headway. Including the 7-hour
      // overnight gap would report ~80.
      expect(status.averageHeadwayMinutes, 60);
    });

    test('a single daily departure has no headway', () {
      final status = Schedule.statusFor(const [6 * 60], at9am);
      expect(status.averageHeadwayMinutes, isNull);
      expect(status.dailyFrequency, 1);
    });

    test('normalises out-of-range minutes', () {
      final status = Schedule.statusFor(const [1440, 1500], at9am);
      expect(status.firstDepartureMinute, 0);
      expect(status.lastDepartureMinute, 60);
    });
  });

  group('next departure with a connection buffer', () {
    // Transfer board at Solapur: 10:00, 10:20, 11:00.
    final board = [10 * 60, 10 * 60 + 20, 11 * 60];
    final arrivesAt955 = DateTime(2026, 9, 3, 9, 55);

    test('with no buffer the next bus is taken', () {
      final d = Schedule.nextDepartureAfter(board, arrivesAt955)!;
      expect(d.minuteOfDay, 10 * 60);
    });

    test('a 10-minute buffer still allows the 10:00 bus', () {
      final d = Schedule.nextDepartureAfter(board, arrivesAt955,
          bufferMinutes: 10)!;
      // 09:55 + 10 = 10:05, so 10:00 is no longer reachable.
      expect(d.minuteOfDay, 10 * 60 + 20);
    });

    test('a long buffer skips to a later bus', () {
      final d = Schedule.nextDepartureAfter(board, arrivesAt955,
          bufferMinutes: 40)!;
      expect(d.minuteOfDay, 11 * 60);
    });

    test('minutesUntil is measured from now, including the wait', () {
      final d = Schedule.nextDepartureAfter(board, arrivesAt955,
          bufferMinutes: 10)!;
      // 09:55 to 10:20 is 25 minutes of real waiting.
      expect(d.minutesUntil, 25);
    });

    test('an empty board yields null', () {
      expect(Schedule.nextDepartureAfter(const [], arrivesAt955), isNull);
    });
  });

  group('clock formatting', () {
    test('24-hour form is zero-padded', () {
      expect(Schedule.formatClock24(0), '00:00');
      expect(Schedule.formatClock24(5 * 60 + 30), '05:30');
      expect(Schedule.formatClock24(23 * 60 + 59), '23:59');
    });

    test('12-hour form uses 12 rather than 0', () {
      expect(Schedule.formatClock(0), '12:00 AM');
      expect(Schedule.formatClock(12 * 60), '12:00 PM');
      expect(Schedule.formatClock(13 * 60 + 5), '1:05 PM');
      expect(Schedule.formatClock(23 * 60 + 45), '11:45 PM');
    });
  });

  group('duration formatting', () {
    test('zero and negative read as now', () {
      expect(Schedule.formatDuration(0), 'now');
      expect(Schedule.formatDuration(-5), 'now');
    });

    test('under an hour is minutes', () {
      expect(Schedule.formatDuration(45), '45m');
    });

    test('a whole hour omits minutes', () {
      expect(Schedule.formatDuration(120), '2h');
    });

    test('hours and minutes combine', () {
      expect(Schedule.formatDuration(155), '2h 35m');
    });

    test('over a day shows days', () {
      expect(Schedule.formatDuration(1500), '1d 1h');
      expect(Schedule.formatDuration(1440), '1d');
    });
  });

  group('relative phrasing', () {
    test('an imminent departure says boarding now', () {
      expect(Schedule.formatRelative(Schedule.resolve(9 * 60, at9am)),
          'Boarding now');
    });

    test('a near departure counts down', () {
      expect(Schedule.formatRelative(Schedule.resolve(9 * 60 + 25, at9am)),
          'in 25m');
    });

    test('a distant tomorrow departure names the clock time', () {
      final phrase =
          Schedule.formatRelative(Schedule.resolve(5 * 60, at9am));
      expect(phrase, 'Tomorrow 5:00 AM');
    });

    test('an early-hours departure late at night counts down instead', () {
      // 45 minutes away, so a countdown is more useful than "Tomorrow 12:30 AM".
      expect(Schedule.formatRelative(Schedule.resolve(30, at1145pm)), 'in 45m');
    });
  });

  group('day part', () {
    test('buckets the day', () {
      expect(Schedule.dayPart(2 * 60), DayPart.night);
      expect(Schedule.dayPart(8 * 60), DayPart.morning);
      expect(Schedule.dayPart(14 * 60), DayPart.afternoon);
      expect(Schedule.dayPart(18 * 60), DayPart.evening);
      expect(Schedule.dayPart(22 * 60), DayPart.night);
    });

    test('every bucket has a greeting', () {
      for (final part in DayPart.values) {
        expect(part.greeting, isNotEmpty);
      }
    });
  });

  group('adding minutes', () {
    test('wraps across midnight', () {
      expect(Schedule.addMinutes(23 * 60 + 30, 60), 30);
      expect(Schedule.addMinutes(0, -30), 23 * 60 + 30);
    });
  });

  group('window membership', () {
    test('a normal window is half-open', () {
      expect(Schedule.isWithinWindow(9 * 60, 8 * 60, 11 * 60), isTrue);
      expect(Schedule.isWithinWindow(8 * 60, 8 * 60, 11 * 60), isTrue);
      expect(Schedule.isWithinWindow(11 * 60, 8 * 60, 11 * 60), isFalse);
    });

    test('a window spanning midnight works both sides', () {
      expect(Schedule.isWithinWindow(23 * 60, 22 * 60, 4 * 60), isTrue);
      expect(Schedule.isWithinWindow(2 * 60, 22 * 60, 4 * 60), isTrue);
      expect(Schedule.isWithinWindow(12 * 60, 22 * 60, 4 * 60), isFalse);
    });

    test('an empty window means the whole day', () {
      expect(Schedule.isWithinWindow(15 * 60, 0, 0), isTrue);
    });
  });

  group('overnight journeys', () {
    test('a long evening departure is overnight', () {
      // 21:00 Nagpur–Mumbai, 14 hours.
      expect(Schedule.isOvernightJourney(21 * 60, 14 * 60), isTrue);
    });

    test('a trip crossing midnight is overnight', () {
      // 23:00 departure, 3 hours.
      expect(Schedule.isOvernightJourney(23 * 60, 3 * 60), isTrue);
    });

    test('a daytime trip is not', () {
      expect(Schedule.isOvernightJourney(9 * 60, 4 * 60), isFalse);
      expect(Schedule.isOvernightJourney(14 * 60, 2 * 60), isFalse);
    });
  });

  group('duration sanitising', () {
    test('never returns zero or negative', () {
      expect(Schedule.sanitiseDuration(0), 1);
      expect(Schedule.sanitiseDuration(-100), 1);
    });

    test('caps absurd values', () {
      expect(Schedule.sanitiseDuration(999999), 3 * 1440);
    });

    test('passes plausible values through', () {
      expect(Schedule.sanitiseDuration(240), 240);
    });
  });
}
