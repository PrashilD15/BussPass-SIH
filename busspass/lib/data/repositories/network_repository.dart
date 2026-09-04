/// Loading and caching the transit network.
///
/// The app is **offline-first**. The bundled `assets/data/network.json` is the
/// source of truth for stops, corridors, schedules, and departure boards, so
/// journey planning, fares, timetables, and the map all work on a plane or in a
/// village with no signal.
///
/// Firestore is an *overlay*, not a dependency. When it is reachable and has
/// been seeded, its documents replace matching bundled records and add new ones;
/// when it is not, nothing degrades. This is the opposite of the previous
/// behaviour, where an unseeded collection or a dropped connection produced
/// empty screens.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:busspass/data/models/network_models.dart';

/// Where a loaded network came from, so the UI can be honest about freshness.
enum NetworkSource {
  /// Bundled asset only.
  bundled('Offline data'),

  /// Bundled asset with a Firestore overlay applied.
  merged('Live data'),

  /// Nothing loaded.
  none('No data');

  const NetworkSource(this.label);
  final String label;
}

/// A loaded network plus its provenance.
class NetworkSnapshot {
  final TransitNetwork network;
  final NetworkSource source;
  final DateTime loadedAt;

  /// Non-null when the Firestore overlay was attempted and failed. Surfaced as
  /// a quiet banner rather than an error screen, because the app still works.
  final String? overlayError;

  /// Counts of what the overlay contributed, for diagnostics.
  final int overlayStops;
  final int overlayRoutes;

  const NetworkSnapshot({
    required this.network,
    required this.source,
    required this.loadedAt,
    this.overlayError,
    this.overlayStops = 0,
    this.overlayRoutes = 0,
  });

  bool get isLive => source == NetworkSource.merged;
}

class NetworkRepository {
  NetworkRepository({
    FirebaseFirestore? firestore,
    AssetBundle? bundle,
  })  : _firestore = firestore,
        _bundle = bundle;

  final FirebaseFirestore? _firestore;
  final AssetBundle? _bundle;

  static const String assetPath = 'assets/data/network.json';

  /// How long to wait for Firestore before falling back to bundled data.
  ///
  /// Kept short deliberately: a rider opening the app at a bus stand should see
  /// their departure board immediately, not after a 30-second timeout.
  static const Duration overlayTimeout = Duration(seconds: 6);

  TransitNetwork? _bundledCache;

  /// Parse the bundled dataset. Cached, since it is immutable reference data.
  Future<TransitNetwork> loadBundled() async {
    final cached = _bundledCache;
    if (cached != null) return cached;

    final bundle = _bundle ?? rootBundle;
    final raw = await bundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final network = TransitNetwork.fromJson(json);
    _bundledCache = network;
    return network;
  }

  /// Load the network, overlaying Firestore when available.
  Future<NetworkSnapshot> load({bool allowOverlay = true}) async {
    final bundled = await loadBundled();

    if (!allowOverlay || _firestore == null) {
      return NetworkSnapshot(
        network: bundled,
        source: NetworkSource.bundled,
        loadedAt: DateTime.now(),
      );
    }

    try {
      final overlay = await _fetchOverlay().timeout(overlayTimeout);
      if (overlay.stops.isEmpty && overlay.routes.isEmpty) {
        // Firestore reachable but unseeded — bundled data stands.
        return NetworkSnapshot(
          network: bundled,
          source: NetworkSource.bundled,
          loadedAt: DateTime.now(),
        );
      }
      return NetworkSnapshot(
        network: _merge(bundled, overlay),
        source: NetworkSource.merged,
        loadedAt: DateTime.now(),
        overlayStops: overlay.stops.length,
        overlayRoutes: overlay.routes.length,
      );
    } catch (error, stack) {
      // A failed overlay is not a failed load. Log it and carry on offline.
      debugPrint('NetworkRepository: Firestore overlay unavailable — $error');
      assert(() {
        debugPrintStack(stackTrace: stack, label: 'network overlay');
        return true;
      }());
      return NetworkSnapshot(
        network: bundled,
        source: NetworkSource.bundled,
        loadedAt: DateTime.now(),
        overlayError: error.toString(),
      );
    }
  }

  /// Pull the Firestore collections in parallel.
  ///
  /// Reads the same schema the existing `scripts/seed_firestore.js` writes, so
  /// an already-seeded project works with no migration.
  Future<_Overlay> _fetchOverlay() async {
    final db = _firestore!;
    final results = await Future.wait([
      db.collection('bus_stops').get(),
      db.collection('routes').get(),
    ]);

    final stops = <NetworkStop>[];
    for (final doc in results[0].docs) {
      final data = doc.data();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      // Skip rather than throw: one malformed document should not blank the map.
      if (lat == null || lng == null) continue;
      stops.add(NetworkStop(
        id: doc.id,
        name: data['name'] as String? ?? doc.id,
        city: data['city'] as String? ?? '',
        depot: data['depot'] as String? ?? '',
        district: data['district'] as String? ?? '',
        lat: lat,
        lng: lng,
        tier: (data['tier'] as num?)?.toInt() ?? 3,
      ));
    }

    final routes = <TransitRoute>[];
    for (final doc in results[1].docs) {
      final data = doc.data();
      final stopList = (data['stops'] as List<dynamic>? ?? const [])
          .map((e) => RouteStopRef.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((s) => s.stopId.isNotEmpty)
          .toList();
      if (stopList.length < 2) continue;

      routes.add(TransitRoute(
        id: doc.id,
        name: data['name'] as String? ?? doc.id,
        operatorName: data['operator'] as String? ?? 'MSRTC',
        isCorridor: true,
        originStopId: data['origin_stop_id'] as String? ?? stopList.first.stopId,
        destinationStopId:
            data['destination_stop_id'] as String? ?? stopList.last.stopId,
        originCity: data['origin_city'] as String? ?? stopList.first.city,
        destinationCity:
            data['destination_city'] as String? ?? stopList.last.city,
        distanceKm: (data['distance_km'] as num?)?.toDouble() ??
            stopList.last.cumKm,
        busTypes: (data['bus_types'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        stops: stopList,
      ));
    }

    return _Overlay(stops: stops, routes: routes);
  }

  /// Merge the overlay over the bundled network.
  ///
  /// Firestore wins on conflicts, because a seeded project is presumed to be
  /// deliberately curated. Bundled records with no Firestore counterpart are
  /// retained, so the overlay can be partial.
  ///
  /// Services and departure boards are bundled-only: they come from scraped
  /// depot boards that the Firestore schema has no equivalent for. A route that
  /// arrives only from Firestore is given a synthesised service so it is still
  /// plannable rather than being a line on the map nobody can board.
  TransitNetwork _merge(TransitNetwork bundled, _Overlay overlay) {
    final stops = <String, NetworkStop>{
      for (final s in bundled.stops) s.id: s,
    };
    for (final s in overlay.stops) {
      stops[s.id] = s;
    }

    final routes = <String, TransitRoute>{
      for (final r in bundled.routes) r.id: r,
    };
    final newRouteIds = <String>[];
    for (final r in overlay.routes) {
      // Only accept a route whose stops all resolve, or the planner would build
      // legs against phantom stands.
      if (r.stops.any((s) => !stops.containsKey(s.stopId))) continue;
      if (!routes.containsKey(r.id)) newRouteIds.add(r.id);
      routes[r.id] = r;
    }

    final services = List<TransitService>.of(bundled.services);
    for (final routeId in newRouteIds) {
      final route = routes[routeId]!;
      for (final busType in route.busTypes.isEmpty
          ? const ['Ordinary']
          : route.busTypes) {
        services.add(TransitService(
          id: 'overlay::$routeId::$busType',
          routeId: routeId,
          busType: busType,
          source: 'corridor',
          fromStopId: null,
          departures: _synthesiseDepartures(route.distanceKm, busType),
        ));
      }
    }

    return TransitNetwork(
      version: bundled.version,
      generatedAt: bundled.generatedAt,
      operatorName: bundled.operatorName,
      stops: stops.values.toList(),
      routes: routes.values.toList(),
      services: services,
      timetables: bundled.timetables,
    );
  }

  /// Headway-based departures for a route that arrived without a schedule.
  ///
  /// Mirrors the generator in `scripts/build_dataset.js` so a Firestore-only
  /// route behaves like a bundled corridor rather than being unplannable.
  List<int> _synthesiseDepartures(double km, String busType) {
    final (first, last) = switch (km) {
      > 600 => (17 * 60, 22 * 60),
      > 350 => (6 * 60, 22 * 60),
      > 150 => (5 * 60 + 30, 22 * 60 + 30),
      _ => (5 * 60, 23 * 60),
    };
    final tier = ServiceClassCatalog.byKey(busType).tier;
    final base = switch (km) {
      <= 120 => 30,
      <= 250 => 45,
      <= 450 => 90,
      _ => 180,
    };
    final headway = (base * (1 + 0.55 * (tier - 1))).round();

    final out = <int>[];
    for (var t = first; t <= last; t += headway) {
      out.add(t % 1440);
    }
    return out.isEmpty ? [first] : out;
  }
}

class _Overlay {
  final List<NetworkStop> stops;
  final List<TransitRoute> routes;

  const _Overlay({required this.stops, required this.routes});
}
