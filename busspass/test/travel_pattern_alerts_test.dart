import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/services/notification_service.dart';
import 'package:busspass/core/services/travel_pattern_alerts.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/repositories/local_store.dart';

/// A minimal synthetic network so the tests are deterministic — no dependence on
/// the wall clock or the real dataset.
///
/// A → B is a 100 km corridor with an hourly Ordinary service. Alpha is the
/// origin stand, Bravo the destination.
TransitNetwork buildTestNetwork() {
  const stops = [
    NetworkStop(id: 'alpha', name: 'Alpha Stand', city: 'Alpha', depot: 'Alpha',
        district: 'Alpha', lat: 18.0, lng: 73.0, tier: 3),
    NetworkStop(id: 'bravo', name: 'Bravo Stand', city: 'Bravo', depot: 'Bravo',
        district: 'Bravo', lat: 18.0, lng: 74.0, tier: 3),
  ];

  RouteStopRef ref(String id, String city, int seq, double cum) =>
      RouteStopRef(stopId: id, name: '$city Stand', city: city,
          lat: 18.0, lng: 73.0 + (seq - 1), seq: seq, cumKm: cum);

  final route = TransitRoute(
    id: 'alpha-bravo', name: 'Alpha – Bravo', operatorName: 'MSRTC',
    isCorridor: true, originStopId: 'alpha', destinationStopId: 'bravo',
    originCity: 'Alpha', destinationCity: 'Bravo', distanceKm: 100,
    busTypes: const ['Ordinary', 'Shivneri'],
    stops: [
      ref('alpha', 'Alpha', 1, 0),
      ref('bravo', 'Bravo', 2, 100),
    ],
  );

  final services = [
    // Hourly Ordinary from 06:00 to 20:00.
    const TransitService(
      id: 'svc-ab', routeId: 'alpha-bravo', busType: 'Ordinary',
      source: 'corridor', fromStopId: null, departures: [360, 420, 480, 540],
    ),
  ];

  return TransitNetwork(stops: stops, routes: [route], services: services);
}

/// Test double that records scheduling calls without touching any platform
/// channel, so the VM test never hits a MissingPluginException.
class _RecordingNotificationService extends NotificationService {
  final scheduled = <(int, DateTime, String, String)>{};
  final cancelled = <int>{};

  @override
  bool get isInitialised => true;

  @override
  bool get isPermitted => true;

  @override
  Future<void> initialise() async {}

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    AlertChannel channel = AlertChannel.journey,
    String? payload,
  }) async {
    scheduled.add((id, when, title, body));
  }

  @override
  Future<void> cancelId(int id) async => cancelled.add(id);
}

/// A LocalStore whose frequent-search reads come from the in-memory [searches]
/// list. The prefs instance only satisfies the constructor — no prefs are read.
class _MemoryStore extends LocalStore {
  _MemoryStore(super.prefs, this.searches);

  final List<RecentSearch>? searches;

  @override
  List<RecentSearch> readRecentSearches() => searches ?? const [];

  @override
  List<RecentSearch> readFrequentSearches({int limit = 4}) {
    final source = searches ?? const <RecentSearch>[];
    final sorted = [...source]
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.searchedAt.compareTo(a.searchedAt);
      });
    return sorted.where((s) => s.count > 1).take(limit).toList();
  }
}

void main() {
  late JourneyPlanner planner;
  late SharedPreferences prefs;

  setUpAll(() async {
    planner = JourneyPlanner(TransitGraph.build(buildTestNetwork()));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  // Fixed reference time: 06:05 — the next Alpha→Bravo bus is 06:00 passed, so
  // the next one is 07:00, comfortably more than 20 minutes away.
  final fixedNow = DateTime(2026, 9, 3, 6, 5);

  RecentSearch frequentPair() => RecentSearch(
        originStopId: 'alpha',
        originName: 'Alpha',
        destinationStopId: 'bravo',
        destinationName: 'Bravo',
        searchedAt: fixedNow,
        count: 3,
      );

  group('travel pattern alerts', () {
    test('schedules a future-dated boarding reminder for a frequent pair',
        () async {
      final store = _MemoryStore(prefs, [frequentPair()]);
      final notes = _RecordingNotificationService();

      await scheduleTravelPatternAlerts(
        planner: planner,
        store: store,
        notifications: notes,
        arrivalAlertsEnabled: true,
        leadMinutes: 20,
        clock: () => fixedNow,
      );

      expect(notes.scheduled.length, 1,
          reason: 'one frequent pair should schedule one alert');
      final (_, fireAt, title, body) = notes.scheduled.first;
      // 07:00 departure − 20 min = 06:40 > the 06:05 reference time.
      expect(fireAt, DateTime(2026, 9, 3, 6, 40));
      expect(title, contains('Bravo'), reason: 'title names the destination');
      expect(title, contains('07:00'), reason: 'title names the departure time');
      expect(body, contains('Alpha'), reason: 'body names the origin');
    });

    test('does not schedule when the next departure is too soon', () async {
      // 06:55 reference — the next bus is 07:00, only 5 minutes away, so the
      // 06:40 alert time is already in the past and must be dropped.
      final now = DateTime(2026, 9, 3, 6, 55);
      final store = _MemoryStore(prefs, [frequentPair()]);
      final notes = _RecordingNotificationService();

      await scheduleTravelPatternAlerts(
        planner: planner,
        store: store,
        notifications: notes,
        arrivalAlertsEnabled: true,
        leadMinutes: 20,
        clock: () => now,
      );

      expect(notes.scheduled, isEmpty);
      expect(notes.cancelled, contains(NotificationService.idForPattern(
          'alpha>bravo')),
          reason: 'a stale/too-soon pattern alert is cleared');
    });

    test('schedules nothing and cancels all when alerts are disabled',
        () async {
      final store = _MemoryStore(prefs, [frequentPair()]);
      final notes = _RecordingNotificationService();

      await scheduleTravelPatternAlerts(
        planner: planner,
        store: store,
        notifications: notes,
        arrivalAlertsEnabled: false,
        clock: () => fixedNow,
      );

      expect(notes.scheduled, isEmpty);
      expect(notes.cancelled.length,
          NotificationService.patternAlertSlots,
          reason: 'every pattern slot is cancelled when disabled');
    });

    test('single-searched variants are not treated as patterns', () async {
      final store = _MemoryStore(prefs, [
        RecentSearch(
          originStopId: 'alpha',
          originName: 'Alpha',
          destinationStopId: 'bravo',
          destinationName: 'Bravo',
          searchedAt: fixedNow,
          count: 1,
        ),
      ]);
      final notes = _RecordingNotificationService();

      await scheduleTravelPatternAlerts(
        planner: planner,
        store: store,
        notifications: notes,
        arrivalAlertsEnabled: true,
        clock: () => fixedNow,
      );

      expect(notes.scheduled, isEmpty,
          reason: 'a count-1 search is not yet a frequent pattern');
    });

    test('idForPattern is deterministic and within the reserved range', () {
      const key = 'alpha>bravo';
      final a = NotificationService.idForPattern(key);
      final b = NotificationService.idForPattern(key);
      expect(a, b, reason: 'same key maps to the same slot');
      expect(a, greaterThanOrEqualTo(NotificationService.patternAlertBaseId));
      expect(a, lessThan(NotificationService.patternAlertBaseId +
          NotificationService.patternAlertSlots));
    });
  });
}
