/// Riverpod graph for the transit network, planning, live buses, and settings.
///
/// Design rules, all of which the old provider layer violated:
///
///  - **Family keys are value types with `==`.** `roadPolylineProvider` was keyed
///    on `BusRoute`, which had no equality override, so every rebuild was a cache
///    miss and a fresh network call.
///  - **Nothing is fetched more than once.** A journey search ran the same graph
///    query three times: in the search screen, in the provider, then again in the
///    details screen.
///  - **Expensive objects are built once.** The transit graph is constructed
///    exactly once per network load, not per query.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/core/services/bus_simulator.dart';
import 'package:busspass/core/services/notification_service.dart';
import 'package:busspass/core/services/transit_detection_service.dart';
import 'package:busspass/core/services/travel_pattern_alerts.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/repositories/local_store.dart';
import 'package:busspass/data/repositories/network_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Infrastructure
// ─────────────────────────────────────────────────────────────────────────────

final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  // Firestore is optional. On a machine with no Firebase configuration the app
  // must still run entirely on bundled data rather than crashing at startup.
  try {
    return FirebaseFirestore.instance;
  } catch (error) {
    debugPrint('Firestore unavailable — running offline. $error');
    return null;
  }
});

final realtimeDatabaseProvider = Provider<FirebaseDatabase?>((ref) {
  try {
    return FirebaseDatabase.instance;
  } catch (error) {
    debugPrint('Realtime Database unavailable — using the simulator. $error');
    return null;
  }
});

/// Local persistence. Overridden with a concrete instance in `main()`, so no
/// screen has to await it.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw StateError(
    'localStoreProvider was not overridden. Call LocalStore.open() in main() '
    'and pass it via ProviderScope overrides.',
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  // Fire and forget: the app is fully usable while this settles, and it never
  // throws.
  service.initialise();
  return service;
});

// ─────────────────────────────────────────────────────────────────────────────
// Network
// ─────────────────────────────────────────────────────────────────────────────

final networkRepositoryProvider = Provider<NetworkRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return NetworkRepository(
    firestore: ref.watch(firestoreProvider),
    // Persistent stale-while-revalidate cache: a fresh overlay skips the
    // Firestore fetch (fewer reads, faster launch); a stale one still serves
    // last-known live data if the network is down.
    readOverlayCache: store.readOverlayCache,
    readOverlayCachedAt: store.readOverlayCachedAt,
    writeOverlayCache: store.writeOverlayCache,
  );
});

/// The loaded network, with its provenance.
///
/// Bundled data always resolves; the Firestore overlay is best-effort. Keys off
/// [effectiveSTCProvider] so a manual state switch (not just GPS detection)
/// reloads the whole chain.
final networkSnapshotProvider = FutureProvider<NetworkSnapshot>((ref) async {
  final stc = ref.watch(effectiveSTCProvider);
  final snapshot = await ref.watch(networkRepositoryProvider).load(assetPath: stc.networkAsset);
  // The offset caches key on service ids, which are only unique within one
  // dataset version.
  JourneyPlanner.invalidateCaches();
  BusSimulator.invalidateCaches();
  return snapshot;
});

/// The network itself, for the common case where provenance is irrelevant.
final networkProvider = FutureProvider<TransitNetwork>((ref) async {
  final snapshot = await ref.watch(networkSnapshotProvider.future);
  return snapshot.network;
});

/// The transit graph. Built once per network load.
final transitGraphProvider = FutureProvider<TransitGraph>((ref) async {
  final network = await ref.watch(networkProvider.future);
  return TransitGraph.build(network);
});

final journeyPlannerProvider = FutureProvider<JourneyPlanner>((ref) async {
  final graph = await ref.watch(transitGraphProvider.future);
  return JourneyPlanner(graph);
});

/// All stops, sorted for display.
final allStopsProvider = FutureProvider<List<NetworkStop>>((ref) async {
  final network = await ref.watch(networkProvider.future);
  return network.stops;
});

/// Stop lookup by id.
final stopProvider = FutureProvider.family<NetworkStop?, String>(
  (ref, stopId) async {
    final network = await ref.watch(networkProvider.future);
    return network.stopById(stopId);
  },
);

/// Stop search. The query is the family key, so results are memoised per query.
final stopSearchProvider =
    FutureProvider.family<List<NetworkStop>, String>((ref, query) async {
  final network = await ref.watch(networkProvider.future);
  return network.searchStops(query, limit: 25);
});

/// Services calling at a stop, with the next departure for each.
final departuresFromStopProvider =
    FutureProvider.family<List<StopDeparture>, String>((ref, stopId) async {
  final network = await ref.watch(networkProvider.future);
  final graph = await ref.watch(transitGraphProvider.future);
  final now = ref.watch(clockProvider);

  final out = <StopDeparture>[];
  for (final call in graph.callsAt(stopId)) {
    final route = call.route;
    final service = call.service;

    // The far terminus in this service's direction of travel.
    final isReversed = service.fromStopId != null &&
        route.stopRefById(service.fromStopId!)?.seq != 1;
    final terminusRef = isReversed ? route.stops.first : route.stops.last;
    if (terminusRef.stopId == stopId) continue;

    final status = Schedule.statusFor(service.departures, now);
    final next = status.next;
    if (next == null) continue;

    final boardRef = route.stopRefById(stopId);
    final distanceKm = boardRef == null
        ? route.distanceKm
        : (terminusRef.cumKm - boardRef.cumKm).abs();

    out.add(StopDeparture(
      route: route,
      service: service,
      destinationName: network.stopById(terminusRef.stopId)?.city ??
          terminusRef.city,
      next: next,
      dailyFrequency: status.dailyFrequency,
      distanceKm: distanceKm,
    ));
  }

  out.sort((a, b) => a.next.minutesUntil.compareTo(b.next.minutesUntil));
  return out;
});

/// One row of a stop's departure board.
class StopDeparture {
  final TransitRoute route;
  final TransitService service;
  final String destinationName;
  final Departure next;
  final int dailyFrequency;
  final double distanceKm;

  const StopDeparture({
    required this.route,
    required this.service,
    required this.destinationName,
    required this.next,
    required this.dailyFrequency,
    required this.distanceKm,
  });
}

/// Scraped departure-board rows for a depot.
final timetableRowsProvider =
    FutureProvider.family<List<TimetableRow>, String>((ref, stopId) async {
  final network = await ref.watch(networkProvider.future);
  return network.timetablesFrom(stopId);
});

/// Depots that have a published board.
final timetableOriginsProvider =
    FutureProvider<List<NetworkStop>>((ref) async {
  final network = await ref.watch(networkProvider.future);
  return network.timetableOrigins;
});

// ─────────────────────────────────────────────────────────────────────────────
// Clock
// ─────────────────────────────────────────────────────────────────────────────

/// A ticking clock, so countdowns update on their own.
///
/// The old timetable screen had a comment claiming it refreshed every minute but
/// used a single `Future.delayed(1 second)` that fired once and never again.
/// Every relative time in the app now derives from this.
///
/// Exposed as a synchronous `DateTime` rather than an `AsyncValue`, because a
/// clock is never "loading" — there is always a current time. That keeps every
/// consumer free of a pointless null check.
class ClockNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => state = DateTime.now(),
    );
    ref.onDispose(() => _timer?.cancel());
    return DateTime.now();
  }

  /// Force an immediate tick, e.g. on app resume, where up to 20 seconds of
  /// staleness would be visible.
  void refresh() => state = DateTime.now();
}

final clockProvider =
    NotifierProvider<ClockNotifier, DateTime>(ClockNotifier.new);

/// A faster clock for live tracking, where a 20-second granularity is too coarse.
final liveClockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(
    const Duration(seconds: 2),
    (_) => DateTime.now(),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Journey planning
// ─────────────────────────────────────────────────────────────────────────────

/// A journey query. A value type with structural equality, so the same search
/// resolves from cache instead of re-running the graph search.
@immutable
class JourneyQuery {
  final String originId;
  final String destinationId;

  /// Departure time, rounded to the minute so a ticking clock does not
  /// invalidate the cache every second.
  final DateTime departAfter;

  final JourneyPreference preference;
  final int adultCount;
  final int ladyCount;
  final int childCount;

  JourneyQuery({
    required this.originId,
    required this.destinationId,
    required DateTime departAfter,
    this.preference = JourneyPreference.fastest,
    this.adultCount = 1,
    this.ladyCount = 0,
    this.childCount = 0,
  }) : departAfter = DateTime(
          departAfter.year,
          departAfter.month,
          departAfter.day,
          departAfter.hour,
          departAfter.minute,
        );

  @override
  bool operator ==(Object other) =>
      other is JourneyQuery &&
      other.originId == originId &&
      other.destinationId == destinationId &&
      other.departAfter == departAfter &&
      other.preference == preference &&
      other.adultCount == adultCount &&
      other.ladyCount == ladyCount &&
      other.childCount == childCount;

  @override
  int get hashCode => Object.hash(
        originId,
        destinationId,
        departAfter,
        preference,
        adultCount,
        ladyCount,
        childCount,
      );

  @override
  String toString() =>
      'JourneyQuery($originId → $destinationId, '
      '${Schedule.formatClock24(Schedule.minuteOfDay(departAfter))}, '
      '${preference.name})';
}

/// Plan a journey. Runs the graph search exactly once per distinct query.
final journeyPlanProvider =
    FutureProvider.family<List<Itinerary>, JourneyQuery>((ref, query) async {
  final planner = await ref.watch(journeyPlannerProvider.future);
  return planner.plan(query: query);
});

// ─────────────────────────────────────────────────────────────────────────────
// Live buses
// ─────────────────────────────────────────────────────────────────────────────

final busSimulatorProvider = FutureProvider<BusSimulator>((ref) async {
  final network = await ref.watch(networkProvider.future);
  return BusSimulator(network: network);
});

/// Where live positions come from.
enum LiveSource {
  /// Firebase RTDB, written by POS devices.
  realtimeDatabase('Live GPS'),

  /// The in-app simulator.
  simulator('Simulated'),

  /// Nothing available.
  none('Unavailable');

  const LiveSource(this.label);
  final String label;
}

/// The live fleet, with its source.
///
/// RTDB is preferred when it has data; the simulator fills in otherwise. Both
/// are exposed through one stream so no screen branches on the source, and the
/// source is reported so the UI can label simulated data honestly.
final liveFleetProvider = StreamProvider<LiveFleet>((ref) async* {
  final database = ref.watch(realtimeDatabaseProvider);

  if (database != null) {
    // Race the RTDB against a short timeout. A configured-but-empty database
    // must not leave the map blank while it waits.
    try {
      final probe = await database
          .ref('buses')
          .limitToFirst(1)
          .get()
          .timeout(const Duration(seconds: 4));

      if (probe.exists && probe.value != null) {
        yield* database.ref('buses').onValue.map((event) {
          final raw = event.snapshot.value;
          if (raw is! Map) {
            return LiveFleet(buses: const [], source: LiveSource.none);
          }
          final buses = <LiveBus>[];
          raw.forEach((key, value) {
            if (value is Map) {
              final bus = LiveBus.fromRtdb(key.toString(), value);
              if (bus != null) buses.add(bus);
            }
          });
          return LiveFleet(
            buses: buses,
            source: LiveSource.realtimeDatabase,
          );
        });
        return;
      }
    } catch (error) {
      debugPrint('RTDB probe failed — $error');
    }
  }

  // Yield an empty fleet if RTDB is unavailable or empty.
  yield LiveFleet(buses: const [], source: LiveSource.none);
});

/// A fleet snapshot with provenance.
class LiveFleet {
  final List<LiveBus> buses;
  final LiveSource source;

  const LiveFleet({required this.buses, required this.source});

  static const LiveFleet empty =
      LiveFleet(buses: [], source: LiveSource.none);

  bool get isSimulated => source == LiveSource.simulator;

  List<LiveBus> onRoute(String routeId) =>
      buses.where((b) => b.routeId == routeId).toList();

  LiveBus? byId(String busId) {
    for (final bus in buses) {
      if (bus.id == busId) return bus;
    }
    return null;
  }

  /// Buses within [radiusKm] of a point, nearest first.
  List<LiveBus> near(GeoPoint point, {double radiusKm = 6}) {
    final scored = buses
        .map((b) => (bus: b, km: Geo.distanceKm(point, b.point)))
        .where((e) => e.km <= radiusKm)
        .toList()
      ..sort((a, b) => a.km.compareTo(b.km));
    return scored.map((e) => e.bus).toList();
  }
}

/// Buses on one route.
final busesOnRouteProvider =
    Provider.family<List<LiveBus>, String>((ref, routeId) {
  final fleet = ref.watch(liveFleetProvider).value ?? LiveFleet.empty;
  return fleet.onRoute(routeId);
});

/// A single tracked bus.
final trackedBusProvider =
    Provider.family<LiveBus?, String>((ref, busId) {
  final fleet = ref.watch(liveFleetProvider).value ?? LiveFleet.empty;
  return fleet.byId(busId);
});

/// Whether the rider appears to be aboard a bus right now.
///
/// Combines the position stream, the live fleet, and the route corridors into
/// [TransitDetectionService]'s inference. The home screen uses this to offer
/// "start tracking" the moment a match is strong, so tracking never depends on
/// the rider remembering to find the bus on the map.
///
/// Built so the detector is created **once** and fed continuously — `ref.listen`
/// rather than `ref.watch` inside the stream, because rebuilding the service on
/// every 3-second fleet tick would reset its speed trail and it would never
/// reach the sustained-speed threshold that confirms boarding.
final transitDetectionProvider =
    StreamProvider<TransitDetection>((ref) {
  final controller = StreamController<TransitDetection>.broadcast();
  TransitDetectionService? service;
  List<LiveBus> pendingFleet = const [];

  Future<void> ensureService() async {
    if (service != null) return;
    final network = await ref.read(networkProvider.future);
    final s = TransitDetectionService(network: network);
    s.updateFleet(pendingFleet);
    s.detections.listen((d) {
      if (!controller.isClosed) controller.add(d);
    });
    service = s;
  }

  ref.listen<AsyncValue<LiveFleet>>(liveFleetProvider, (_, next) {
    final fleet = next.value;
    if (fleet == null) return;
    pendingFleet = fleet.buses;
    service?.updateFleet(fleet.buses);
  });

  ref.listen<AsyncValue<Position>>(riderPositionStreamProvider, (_, next) {
    final p = next.value;
    if (p == null) return;
    unawaited(ensureService().then((_) => service?.addPosition(
          point: GeoPoint(p.latitude, p.longitude),
          speedKmph: p.speed,
          heading: p.heading,
        )));
  });

  unawaited(ensureService());

  ref.onDispose(() {
    unawaited(controller.close());
    unawaited(service?.dispose() ?? Future.value());
  });

  return controller.stream;
});

/// When the rider last dismissed the boarding prompt, so we don't nag.
class BoardingDismissedNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void dismiss() => state = DateTime.now();
}

final boardingPromptDismissedAtProvider =
    NotifierProvider<BoardingDismissedNotifier, DateTime?>(
        BoardingDismissedNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Rider location
// ─────────────────────────────────────────────────────────────────────────────

/// Outcome of a location request, so the UI can explain a refusal rather than
/// silently showing nothing.
sealed class LocationResult {
  const LocationResult();
}

class LocationAvailable extends LocationResult {
  final Position position;
  const LocationAvailable(this.position);

  GeoPoint get point => GeoPoint(position.latitude, position.longitude);
}

class LocationDenied extends LocationResult {
  /// True when the rider chose "never ask again", so the app must send them to
  /// system settings rather than re-prompting.
  final bool permanently;
  const LocationDenied({this.permanently = false});
}

class LocationServiceOff extends LocationResult {
  const LocationServiceOff();
}

class LocationFailed extends LocationResult {
  final String reason;
  const LocationFailed(this.reason);
}

/// A one-shot location fix.
final riderLocationProvider = FutureProvider<LocationResult>((ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationServiceOff();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationDenied();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationDenied(permanently: true);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LocationAvailable(position);
  } on TimeoutException {
    // A last known fix is far better than nothing for snapping to a nearby stop.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LocationAvailable(last);
    return const LocationFailed('Could not get a GPS fix');
  } catch (error) {
    return LocationFailed(error.toString());
  }
});

/// A continuous position stream, for live navigation.
final riderPositionStreamProvider =
    StreamProvider.autoDispose<Position>((ref) async* {
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return;
  }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      // 25 m keeps updates frequent enough for a progress bar without waking the
      // GPS on every metre.
      distanceFilter: 25,
    ),
  );
});

/// The nearest stop to the rider, with the distance so the caller can reject an
/// implausible match.
final nearestStopProvider =
    FutureProvider<({NetworkStop stop, double distanceKm})?>((ref) async {
  final location = await ref.watch(riderLocationProvider.future);
  if (location is! LocationAvailable) return null;
  final graph = await ref.watch(transitGraphProvider.future);
  return graph.nearestStop(location.point);
});

/// Stops near the rider.
final nearbyStopsProvider = FutureProvider<
    List<({NetworkStop stop, double distanceKm})>>((ref) async {
  final location = await ref.watch(riderLocationProvider.future);
  if (location is! LocationAvailable) return const [];
  final graph = await ref.watch(transitGraphProvider.future);
  return graph.stopsNear(location.point, radiusKm: 40, limit: 15);
});

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(localStoreProvider).readSettings();

  Future<void> _persist(AppSettings next) async {
    state = next;
    await ref.read(localStoreProvider).writeSettings(next);
  }

  Future<void> setLocale(String code) =>
      _persist(state.copyWith(localeCode: code));

  Future<void> setThemeMode(AppThemeMode mode) =>
      _persist(state.copyWith(themeMode: mode));

  Future<void> setRiderCategory(RiderCategory category) =>
      _persist(state.copyWith(riderCategory: category));

  Future<void> setJourneyPreference(JourneyPreference preference) =>
      _persist(state.copyWith(journeyPreference: preference.name));

  Future<void> setArrivalAlerts(bool enabled) =>
      _persist(state.copyWith(arrivalAlerts: enabled));

  Future<void> setArrivalAlertLead(int minutes) =>
      _persist(state.copyWith(arrivalAlertLeadMinutes: minutes));

  Future<void> setHaltAlerts(bool enabled) =>
      _persist(state.copyWith(haltAlerts: enabled));

  Future<void> setDelayAlerts(bool enabled) =>
      _persist(state.copyWith(delayAlerts: enabled));

  Future<void> setReduceMotion(bool enabled) =>
      _persist(state.copyWith(reduceMotion: enabled));

  Future<void> setLargeText(bool enabled) =>
      _persist(state.copyWith(largeText: enabled));

  Future<void> setEmergencyContact({
    required String name,
    required String phone,
  }) =>
      _persist(state.copyWith(
        emergencyContactName: name,
        emergencyContactPhone: phone,
      ));

  Future<void> setDataCollectionConsent(bool consented) =>
      _persist(state.copyWith(dataCollectionConsent: consented));

  Future<void> setHasSeenPrivacyConsent(bool seen) =>
      _persist(state.copyWith(hasSeenPrivacyConsent: seen));
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// The rider's ranking preference, resolved from settings.
final journeyPreferenceProvider = Provider<JourneyPreference>((ref) {
  final name = ref.watch(settingsProvider).journeyPreference;
  return JourneyPreference.values.firstWhere(
    (p) => p.name == name,
    orElse: () => JourneyPreference.fastest,
  );
});

/// Schedules boarding reminders for frequently-searched travel patterns.
///
/// Recomputes whenever the planner, the arrival-alert setting, or the recent
/// searches change, and is failure-tolerant: a denial or plugin failure only
/// means no alert, never a crash. It deliberately does not await the network
/// load itself — it just no-ops until the planner is ready.
final travelPatternAlertsProvider = Provider<void>((ref) {
  ref.watch(journeyPlannerProvider);
  ref.watch(settingsProvider.select((s) => s.arrivalAlerts));
  ref.watch(recentSearchesProvider);

  final store = ref.read(localStoreProvider);
  final notifications = ref.read(notificationServiceProvider);
  final enabled = ref.read(settingsProvider).arrivalAlerts;
  final lead = ref.read(settingsProvider).arrivalAlertLeadMinutes;

  final planner = ref.read(journeyPlannerProvider).value;
  if (planner == null) return;

  unawaited(
    scheduleTravelPatternAlerts(
      planner: planner,
      store: store,
      notifications: notifications,
      arrivalAlertsEnabled: enabled,
      leadMinutes: lead,
    ),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Tickets, saved places, history
// ─────────────────────────────────────────────────────────────────────────────

class TicketsNotifier extends Notifier<List<Ticket>> {
  @override
  List<Ticket> build() => ref.read(localStoreProvider).readTickets();

  Future<void> add(Ticket ticket) async {
    await ref.read(localStoreProvider).addTicket(ticket);
    state = ref.read(localStoreProvider).readTickets();

    // Book a boarding reminder immediately, so the rider is told to head for the
    // stand even if they never reopen the app.
    final settings = ref.read(settingsProvider);
    if (settings.arrivalAlerts && !ticket.isPass) {
      await ref.read(notificationServiceProvider).scheduleBoardingReminder(
            ticketId: ticket.id,
            originName: ticket.originName,
            departsAt: ticket.departsAt,
          );
    }
  }

  Future<void> update(Ticket ticket) async {
    await ref.read(localStoreProvider).updateTicket(ticket);
    state = ref.read(localStoreProvider).readTickets();
  }

  Future<void> cancel(String ticketId) async {
    final store = ref.read(localStoreProvider);
    final existing = state.firstWhere(
      (t) => t.id == ticketId,
      orElse: () => throw StateError('No ticket $ticketId'),
    );
    await store.updateTicket(
        existing.copyWith(status: TicketStatus.cancelled));
    await ref.read(notificationServiceProvider)
        .cancelJourneyAlerts(ticketId);
    state = store.readTickets();
  }

  Future<void> markValidated(String ticketId, String validatedBy) async {
    final store = ref.read(localStoreProvider);
    final existing = state.firstWhere((t) => t.id == ticketId);
    await store.updateTicket(existing.copyWith(
      status: TicketStatus.active,
      validatedAt: DateTime.now(),
      validatedBy: validatedBy,
    ));
    state = store.readTickets();
  }

  Future<void> remove(String ticketId) async {
    await ref.read(localStoreProvider).removeTicket(ticketId);
    state = ref.read(localStoreProvider).readTickets();
  }
}

final ticketsProvider =
    NotifierProvider<TicketsNotifier, List<Ticket>>(TicketsNotifier.new);

/// Tickets grouped by whether they are still usable.
final ticketBucketsProvider = Provider<
    ({List<Ticket> live, List<Ticket> past})>((ref) {
  final tickets = ref.watch(ticketsProvider);
  final now = ref.watch(clockProvider);

  final live = <Ticket>[];
  final past = <Ticket>[];
  for (final ticket in tickets) {
    if (ticket.statusAt(now).isLive) {
      live.add(ticket);
    } else {
      past.add(ticket);
    }
  }
  live.sort((a, b) => a.departsAt.compareTo(b.departsAt));
  past.sort((a, b) => b.departsAt.compareTo(a.departsAt));
  return (live: live, past: past);
});

/// The ticket for the journey the rider is on right now, if any.
final activeTicketProvider = Provider<Ticket?>((ref) {
  final now = ref.watch(clockProvider);
  final live = ref.watch(ticketBucketsProvider).live;
  for (final ticket in live) {
    if (ticket.statusAt(now) == TicketStatus.active) return ticket;
  }
  // Otherwise the next one departing, if it is imminent.
  for (final ticket in live) {
    if (ticket.minutesUntilDeparture(now) <= 90) return ticket;
  }
  return null;
});

class SavedPlacesNotifier extends Notifier<List<SavedPlace>> {
  @override
  List<SavedPlace> build() => ref.read(localStoreProvider).readSavedPlaces();

  Future<void> save(SavedPlace place) async {
    await ref.read(localStoreProvider).addSavedPlace(place);
    state = ref.read(localStoreProvider).readSavedPlaces();
  }

  Future<void> remove(String id) async {
    await ref.read(localStoreProvider).removeSavedPlace(id);
    state = ref.read(localStoreProvider).readSavedPlaces();
  }

  SavedPlace? byKind(SavedPlaceKind kind) {
    for (final place in state) {
      if (place.kind == kind) return place;
    }
    return null;
  }
}

final savedPlacesProvider =
    NotifierProvider<SavedPlacesNotifier, List<SavedPlace>>(
        SavedPlacesNotifier.new);

class RecentSearchesNotifier extends Notifier<List<RecentSearch>> {
  @override
  List<RecentSearch> build() =>
      ref.read(localStoreProvider).readRecentSearches();

  Future<void> record({
    required NetworkStop origin,
    required NetworkStop destination,
  }) async {
    final search = RecentSearch(
      originStopId: origin.id,
      originName: origin.city,
      destinationStopId: destination.id,
      destinationName: destination.city,
      searchedAt: DateTime.now(),
    );
    await ref.read(localStoreProvider).recordSearch(search);
    state = ref.read(localStoreProvider).readRecentSearches();

    final settings = ref.read(settingsProvider);
    if (settings.dataCollectionConsent) {
      final user = ref.read(authRepositoryProvider).currentUser;
      final firestore = ref.read(firestoreProvider);
      if (user != null && firestore != null) {
        try {
          await firestore
              .collection('users')
              .doc(user.uid)
              .collection('recent_searches')
              .add(search.toJson());
        } catch (e) {
          debugPrint('Failed to sync search to Firestore: $e');
        }
      }
    }
  }

  Future<void> clear() async {
    await ref.read(localStoreProvider).clearRecentSearches();
    state = const [];

    final settings = ref.read(settingsProvider);
    if (settings.dataCollectionConsent) {
      final user = ref.read(authRepositoryProvider).currentUser;
      final firestore = ref.read(firestoreProvider);
      if (user != null && firestore != null) {
        try {
          final snapshot = await firestore
              .collection('users')
              .doc(user.uid)
              .collection('recent_searches')
              .get();
          for (final doc in snapshot.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Failed to clear searches from Firestore: $e');
        }
      }
    }
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<RecentSearch>>(
        RecentSearchesNotifier.new);

/// Frequently repeated searches, for home-screen shortcuts.
final frequentSearchesProvider = Provider<List<RecentSearch>>((ref) {
  ref.watch(recentSearchesProvider);
  return ref.read(localStoreProvider).readFrequentSearches();
});

final journeyHistoryProvider = Provider<List<JourneyRecord>>((ref) {
  ref.watch(ticketsProvider);
  return ref.read(localStoreProvider).readJourneyHistory();
});

final travelTotalsProvider = Provider<
    ({int journeys, double distanceKm, int fareSpent, int minutesTravelled})>(
  (ref) {
    ref.watch(journeyHistoryProvider);
    return ref.read(localStoreProvider).travelTotals();
  },
);
