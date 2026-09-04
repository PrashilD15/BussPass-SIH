/// Domain models for the transit network.
///
/// These are loaded from the bundled `assets/data/network.json` and optionally
/// refreshed from Firestore. All are immutable value types with `==`/`hashCode`
/// defined, which matters: the old code keyed a Riverpod `family` provider on a
/// model without equality, so every rebuild was a cache miss and refetched the
/// route geometry over the network.
library;

import 'dart:math' as math;

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/geo.dart';

/// A physical bus stand or stop.
class NetworkStop {
  final String id;
  final String name;
  final String city;
  final String depot;
  final String district;
  final double lat;
  final double lng;

  /// 1 = village stop, 2 = taluka stand, 3 = division/district stand. Used to
  /// size map markers and to break ties in search ranking.
  final int tier;

  const NetworkStop({
    required this.id,
    required this.name,
    required this.city,
    required this.depot,
    required this.district,
    required this.lat,
    required this.lng,
    this.tier = 1,
  });

  GeoPoint get point => GeoPoint(lat, lng);

  /// Name for display, avoiding the redundant "Pune – Pune Bus Stand".
  String get displayName => name;

  /// Secondary line: district when it differs from the city, else the depot.
  String get subtitle {
    if (district.isNotEmpty && district.toLowerCase() != city.toLowerCase()) {
      return '$city · $district';
    }
    return city;
  }

  /// Lowercased haystack for substring search across every identifying field.
  String get searchHaystack =>
      '$name $city $depot $district'.toLowerCase();

  factory NetworkStop.fromJson(Map<String, dynamic> json) => NetworkStop(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        depot: json['depot'] as String? ?? '',
        district: json['district'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        tier: (json['tier'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'depot': depot,
        'district': district,
        'lat': lat,
        'lng': lng,
        'tier': tier,
      };

  @override
  bool operator ==(Object other) => other is NetworkStop && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NetworkStop($id, $name)';
}

/// A stop's position within a route's ordered stop sequence.
class RouteStopRef {
  final String stopId;
  final String name;
  final String city;
  final double lat;
  final double lng;

  /// 1-based position along the route.
  final int seq;

  /// Distance from the route origin measured along the corridor, kilometres.
  /// This is what makes segment fares correct — a short hop costs a short hop.
  final double cumKm;

  const RouteStopRef({
    required this.stopId,
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
    required this.seq,
    required this.cumKm,
  });

  GeoPoint get point => GeoPoint(lat, lng);

  factory RouteStopRef.fromJson(Map<String, dynamic> json) => RouteStopRef(
        stopId: json['stop_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        cumKm: (json['cum_km'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'stop_id': stopId,
        'name': name,
        'city': city,
        'lat': lat,
        'lng': lng,
        'seq': seq,
        'cum_km': cumKm,
      };

  @override
  bool operator ==(Object other) =>
      other is RouteStopRef && other.stopId == stopId && other.seq == seq;

  @override
  int get hashCode => Object.hash(stopId, seq);
}

/// A bus line: an ordered corridor of stops with a known total distance.
class TransitRoute {
  final String id;
  final String name;
  final String operatorName;

  /// True for a curated intercity corridor with an official government road
  /// distance; false for a route derived from a scraped depot board.
  final bool isCorridor;

  final String originStopId;
  final String destinationStopId;
  final String originCity;
  final String destinationCity;

  /// Official road distance, kilometres.
  final double distanceKm;

  /// Service class keys operating on this corridor.
  final List<String> busTypes;

  /// Ordered stop sequence with cumulative distances.
  final List<RouteStopRef> stops;

  const TransitRoute({
    required this.id,
    required this.name,
    required this.operatorName,
    required this.isCorridor,
    required this.originStopId,
    required this.destinationStopId,
    required this.originCity,
    required this.destinationCity,
    required this.distanceKm,
    required this.busTypes,
    required this.stops,
  });

  /// Stops between the termini.
  List<RouteStopRef> get intermediateStops =>
      stops.length <= 2 ? const [] : stops.sublist(1, stops.length - 1);

  /// Geometry for map rendering, following the corridor through every stop.
  List<GeoPoint> get polyline => stops.map((s) => s.point).toList();

  RouteStopRef? stopRefById(String stopId) {
    for (final s in stops) {
      if (s.stopId == stopId) return s;
    }
    return null;
  }

  RouteStopRef? stopRefBySeq(int seq) {
    for (final s in stops) {
      if (s.seq == seq) return s;
    }
    return null;
  }

  /// Distance between two stops on this route, kilometres. `null` when either
  /// stop is not served.
  double? distanceBetween(String fromStopId, String toStopId) {
    final a = stopRefById(fromStopId);
    final b = stopRefById(toStopId);
    if (a == null || b == null) return null;
    return (b.cumKm - a.cumKm).abs();
  }

  /// Cumulative distance to each stop, for ETA offset computation.
  List<double> get cumulativeKm => stops.map((s) => s.cumKm).toList();

  /// Position on the corridor at [roadKm] from the origin.
  ///
  /// **Road kilometres and polyline kilometres are different scales**, and
  /// conflating them is a real bug that shows up as a bus rendered ahead of where
  /// it should be, or a "completed" journey reporting kilometres remaining.
  ///
  /// `cumKm` is a *road* distance: the corridor's published length distributed
  /// across its segments. The polyline is a chain of great-circle hops between
  /// stops, which is always shorter — Mumbai–Pune is 150 km by road and about
  /// 130 km as the crow flies through Panvel and Lonavala.
  ///
  /// The conversion is per segment, because the build step scales each segment
  /// independently: a ghat section is far more indirect than an expressway one on
  /// the same route.
  GeoPoint pointAtRoadKm(double roadKm) {
    if (stops.isEmpty) return const GeoPoint(0, 0);
    if (stops.length == 1) return stops.first.point;

    final target = roadKm.clamp(0.0, distanceKm);

    for (var i = 0; i < stops.length - 1; i++) {
      final from = stops[i];
      final to = stops[i + 1];
      if (target > to.cumKm && i < stops.length - 2) continue;

      final span = to.cumKm - from.cumKm;
      final t = span <= 0 ? 0.0 : ((target - from.cumKm) / span).clamp(0.0, 1.0);
      return Geo.interpolate(from.point, to.point, t);
    }
    return stops.last.point;
  }

  /// Heading of the corridor at [roadKm], degrees from north.
  double bearingAtRoadKm(double roadKm) {
    if (stops.length < 2) return 0;
    final target = roadKm.clamp(0.0, distanceKm);
    for (var i = 0; i < stops.length - 1; i++) {
      if (target <= stops[i + 1].cumKm || i == stops.length - 2) {
        return Geo.bearing(stops[i].point, stops[i + 1].point);
      }
    }
    return Geo.bearing(stops[stops.length - 2].point, stops.last.point);
  }

  /// Convert a polyline projection into a road distance along this corridor.
  double roadKmForProjection(PolylineProjection projection) {
    final index = projection.segmentIndex.clamp(0, stops.length - 2);
    final from = stops[index];
    final to = stops[index + 1];
    return from.cumKm + (to.cumKm - from.cumKm) * projection.segmentT;
  }

  /// Project a point onto this corridor, reporting the result in road
  /// kilometres.
  ///
  /// Returns null when the corridor has no geometry.
  ({double roadKm, double offsetKm})? projectToRoadKm(GeoPoint point) {
    final projection = Geo.projectOnPolyline(point, polyline);
    if (projection == null) return null;
    return (
      roadKm: roadKmForProjection(projection),
      offsetKm: projection.offsetKm,
    );
  }

  /// The sub-polyline between two road distances, for drawing a travelled or
  /// remaining portion.
  List<GeoPoint> polylineBetweenRoadKm(double fromKm, double toKm) {
    final lo = math.min(fromKm, toKm).clamp(0.0, distanceKm);
    final hi = math.max(fromKm, toKm).clamp(0.0, distanceKm);
    if (hi - lo < 1e-6) return [pointAtRoadKm(lo)];

    final out = <GeoPoint>[pointAtRoadKm(lo)];
    for (final stop in stops) {
      if (stop.cumKm > lo && stop.cumKm < hi) out.add(stop.point);
    }
    out.add(pointAtRoadKm(hi));
    return out;
  }

  /// Adult fare across the whole corridor for [serviceClassKey].
  int fullFare(String serviceClassKey) =>
      FareEngine.baseFare(distanceKm, serviceClassKey);

  /// Cheapest and dearest full-corridor adult fare across operating classes.
  ({int min, int max}) get fareRange {
    if (busTypes.isEmpty) {
      final f = fullFare('Ordinary');
      return (min: f, max: f);
    }
    final fares = busTypes.map(fullFare).toList()..sort();
    return (min: fares.first, max: fares.last);
  }

  factory TransitRoute.fromJson(Map<String, dynamic> json) => TransitRoute(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        operatorName: json['operator'] as String? ?? 'MSRTC',
        isCorridor: json['corridor'] as bool? ?? false,
        originStopId: json['origin_stop_id'] as String? ?? '',
        destinationStopId: json['destination_stop_id'] as String? ?? '',
        originCity: json['origin_city'] as String? ?? '',
        destinationCity: json['destination_city'] as String? ?? '',
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        busTypes: (json['bus_types'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        stops: (json['stops'] as List<dynamic>? ?? const [])
            .map((e) => RouteStopRef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'operator': operatorName,
        'corridor': isCorridor,
        'origin_stop_id': originStopId,
        'destination_stop_id': destinationStopId,
        'origin_city': originCity,
        'destination_city': destinationCity,
        'distance_km': distanceKm,
        'bus_types': busTypes,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) => other is TransitRoute && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'TransitRoute($id, ${stops.length} stops)';
}

/// A scheduled operation of one service class on one route.
class TransitService {
  final String id;
  final String routeId;

  /// Canonical service class key.
  final String busType;

  /// `corridor` = synthesised headway from the service window;
  /// `timetable` = real scraped departure board.
  final String source;

  /// For a directional service (a scraped depot board), the stop it originates
  /// from. `null` means the service is modelled as running both ways.
  final String? fromStopId;

  /// Departure times as minutes since midnight, sorted ascending.
  final List<int> departures;

  const TransitService({
    required this.id,
    required this.routeId,
    required this.busType,
    required this.source,
    required this.fromStopId,
    required this.departures,
  });

  /// True when departures come from a real published board rather than a
  /// modelled headway. Surfaced in the UI so a rider knows how much to trust it.
  bool get isPublishedSchedule => source == 'timetable';

  /// True when this is a modelled return working of a published board — the
  /// afternoon Pune→Akole leg of a morning Akole→Pune service.
  bool get isReturnWorking => source == 'return';

  /// True when the service runs one way only, so it cannot be ridden in reverse.
  bool get isDirectional => fromStopId != null;

  /// How much to trust the departure times, for UI phrasing.
  ScheduleConfidence get confidence => switch (source) {
        'timetable' => ScheduleConfidence.published,
        'return' => ScheduleConfidence.modelledReturn,
        _ => ScheduleConfidence.modelledHeadway,
      };

  ServiceClass get serviceClass =>
      ServiceClassCatalog.byKey(busType);

  factory TransitService.fromJson(Map<String, dynamic> json) => TransitService(
        id: json['id'] as String,
        routeId: json['route_id'] as String? ?? '',
        busType: json['bus_type'] as String? ?? 'Ordinary',
        source: json['source'] as String? ?? 'corridor',
        fromStopId: json['from_stop_id'] as String?,
        departures: (json['departures'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toInt())
            .toList()
          ..sort(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'route_id': routeId,
        'bus_type': busType,
        'source': source,
        'from_stop_id': fromStopId,
        'departures': departures,
      };

  @override
  bool operator ==(Object other) => other is TransitService && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How much a departure time can be trusted.
///
/// Presented to the rider rather than hidden, because the difference between a
/// scraped depot board and a modelled headway is the difference between "be at
/// the stand at 14:30" and "buses run about every 45 minutes".
enum ScheduleConfidence {
  /// Times taken from a published MSRTC depot board.
  published('Published timetable', 'From the depot departure board'),

  /// The return leg of a published board, offset by running time and layover.
  modelledReturn('Estimated return', 'Modelled from the outbound service'),

  /// A headway synthesised from the service window.
  modelledHeadway('Estimated frequency', 'Typical service pattern for this route');

  const ScheduleConfidence(this.label, this.explanation);

  final String label;
  final String explanation;

  bool get isPublished => this == ScheduleConfidence.published;
}

/// A row from a scraped depot departure board.
///
/// Kept separately from [TransitService] because a board row is useful even when
/// its destination cannot be resolved to a stand — a rider standing at Sangamner
/// still wants to see that a bus to Kotul leaves at 14:30, whether or not the
/// app can plan a journey there.
class TimetableRow {
  final String originStopId;
  final String originCity;
  final String destination;

  /// Resolved destination stop, or `null` when the scraped name has no stand.
  final String? destinationStopId;

  final List<String> via;
  final String busType;

  /// Distance from the printed board, kilometres. `null` when not printed.
  final double? distanceKm;

  final List<int> departures;

  const TimetableRow({
    required this.originStopId,
    required this.originCity,
    required this.destination,
    required this.destinationStopId,
    required this.via,
    required this.busType,
    required this.distanceKm,
    required this.departures,
  });

  bool get isPlannable => destinationStopId != null;

  ServiceClass get serviceClass => ServiceClassCatalog.byKey(busType);

  /// Adult fare for this board row, when the board printed a distance.
  int? get fare => distanceKm == null
      ? null
      : FareEngine.baseFare(distanceKm!, busType);

  String get viaLabel => via.isEmpty ? '' : 'via ${via.join(', ')}';

  factory TimetableRow.fromJson(Map<String, dynamic> json) => TimetableRow(
        originStopId: json['origin_stop_id'] as String? ?? '',
        originCity: json['origin_city'] as String? ?? '',
        destination: json['destination'] as String? ?? '',
        destinationStopId: json['destination_stop_id'] as String?,
        via: (json['via'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        busType: json['bus_type'] as String? ?? 'Ordinary',
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        departures: (json['departures'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toInt())
            .toList()
          ..sort(),
      );
}

/// Registry of service classes, populated from the bundled dataset.
///
/// A static registry rather than an injected dependency because the class
/// catalogue is fixed reference data — every layer from fare maths to map
/// markers needs it, and threading it through would add noise without adding
/// testability.
class ServiceClassCatalog {
  ServiceClassCatalog._();

  static Map<String, ServiceClass> _classes = _fallback;

  static const Map<String, ServiceClass> _fallback = {
    'Ordinary': ServiceClass(
      key: 'Ordinary', label: 'Ordinary', marathi: 'साधी',
      stageRate: 11.40, ac: false, sleeper: false, tier: 1,
      cruiseKmph: 46, dwellMin: 2.0, stopDensity: 1.0, seats: 52,
    ),
    'Semi Luxury': ServiceClass(
      key: 'Semi Luxury', label: 'Semi Luxury (Hirkani)', marathi: 'हिरकणी',
      stageRate: 13.65, ac: false, sleeper: false, tier: 2,
      cruiseKmph: 52, dwellMin: 1.5, stopDensity: 0.6, seats: 45,
    ),
    'Shivshahi': ServiceClass(
      key: 'Shivshahi', label: 'Shivshahi AC Seater', marathi: 'शिवशाही',
      stageRate: 14.20, ac: true, sleeper: false, tier: 3,
      cruiseKmph: 56, dwellMin: 1.2, stopDensity: 0.4, seats: 43,
    ),
    'Shivshahi Sleeper': ServiceClass(
      key: 'Shivshahi Sleeper', label: 'Shivshahi AC Sleeper',
      marathi: 'शिवशाही शयनयान',
      stageRate: 15.35, ac: true, sleeper: true, tier: 3,
      cruiseKmph: 56, dwellMin: 1.2, stopDensity: 0.3, seats: 30,
    ),
    'Sleeper Seater': ServiceClass(
      key: 'Sleeper Seater', label: 'Ordinary Sleeper-Seater',
      marathi: 'शयनयान-आसनी',
      stageRate: 15.50, ac: false, sleeper: true, tier: 2,
      cruiseKmph: 50, dwellMin: 1.5, stopDensity: 0.5, seats: 36,
    ),
    'Ordinary Sleeper': ServiceClass(
      key: 'Ordinary Sleeper', label: 'Ordinary Sleeper', marathi: 'शयनयान',
      stageRate: 16.75, ac: false, sleeper: true, tier: 2,
      cruiseKmph: 50, dwellMin: 1.5, stopDensity: 0.4, seats: 30,
    ),
    'Shivneri': ServiceClass(
      key: 'Shivneri', label: 'Shivneri AC Seater', marathi: 'शिवनेरी',
      stageRate: 21.25, ac: true, sleeper: false, tier: 4,
      cruiseKmph: 62, dwellMin: 1.0, stopDensity: 0.2, seats: 45,
    ),
    'Shivneri Sleeper': ServiceClass(
      key: 'Shivneri Sleeper', label: 'Shivneri AC Sleeper',
      marathi: 'शिवनेरी शयनयान',
      stageRate: 25.35, ac: true, sleeper: true, tier: 4,
      cruiseKmph: 62, dwellMin: 1.0, stopDensity: 0.2, seats: 30,
    ),
  };

  /// Replace the catalogue from the loaded dataset.
  static void register(List<ServiceClass> classes) {
    if (classes.isEmpty) return;
    _classes = {for (final c in classes) c.key: c};
  }

  /// Look up a class, resolving aliases and falling back to Ordinary.
  static ServiceClass byKey(String key) {
    final direct = _classes[key];
    if (direct != null) return direct;
    final canonical = FareEngine.canonicalKey(key);
    return _classes[canonical] ?? _fallback['Ordinary']!;
  }

  static List<ServiceClass> get all {
    final list = _classes.values.toList()
      ..sort((a, b) {
        final byTier = a.tier.compareTo(b.tier);
        if (byTier != 0) return byTier;
        return a.stageRate.compareTo(b.stageRate);
      });
    return list;
  }
}

/// The whole network, with lookup indices built once at load.
class TransitNetwork {
  final int version;
  final DateTime generatedAt;
  final String operatorName;

  final List<NetworkStop> stops;
  final List<TransitRoute> routes;
  final List<TransitService> services;
  final List<TimetableRow> timetables;

  final Map<String, NetworkStop> _stopIndex;
  final Map<String, TransitRoute> _routeIndex;
  final Map<String, List<TransitService>> _servicesByRoute;
  final Map<String, List<TimetableRow>> _timetablesByOrigin;

  TransitNetwork._({
    required this.version,
    required this.generatedAt,
    required this.operatorName,
    required this.stops,
    required this.routes,
    required this.services,
    required this.timetables,
    required Map<String, NetworkStop> stopIndex,
    required Map<String, TransitRoute> routeIndex,
    required Map<String, List<TransitService>> servicesByRoute,
    required Map<String, List<TimetableRow>> timetablesByOrigin,
  })  : _stopIndex = stopIndex,
        _routeIndex = routeIndex,
        _servicesByRoute = servicesByRoute,
        _timetablesByOrigin = timetablesByOrigin;

  factory TransitNetwork({
    int version = 0,
    DateTime? generatedAt,
    String operatorName = 'MSRTC',
    required List<NetworkStop> stops,
    required List<TransitRoute> routes,
    required List<TransitService> services,
    List<TimetableRow> timetables = const [],
  }) {
    final servicesByRoute = <String, List<TransitService>>{};
    for (final s in services) {
      (servicesByRoute[s.routeId] ??= <TransitService>[]).add(s);
    }
    final timetablesByOrigin = <String, List<TimetableRow>>{};
    for (final t in timetables) {
      (timetablesByOrigin[t.originStopId] ??= <TimetableRow>[]).add(t);
    }

    return TransitNetwork._(
      version: version,
      generatedAt: generatedAt ?? DateTime.now(),
      operatorName: operatorName,
      stops: List.unmodifiable(stops),
      routes: List.unmodifiable(routes),
      services: List.unmodifiable(services),
      timetables: List.unmodifiable(timetables),
      stopIndex: {for (final s in stops) s.id: s},
      routeIndex: {for (final r in routes) r.id: r},
      servicesByRoute: servicesByRoute,
      timetablesByOrigin: timetablesByOrigin,
    );
  }

  static final TransitNetwork empty = TransitNetwork(
    stops: const [],
    routes: const [],
    services: const [],
  );

  bool get isEmpty => stops.isEmpty || routes.isEmpty;

  NetworkStop? stopById(String id) => _stopIndex[id];
  TransitRoute? routeById(String id) => _routeIndex[id];

  List<TransitService> servicesFor(String routeId) =>
      _servicesByRoute[routeId] ?? const [];

  List<TimetableRow> timetablesFrom(String stopId) =>
      _timetablesByOrigin[stopId] ?? const [];

  /// Origin stands that have a scraped departure board, most departures first.
  List<NetworkStop> get timetableOrigins {
    final ids = _timetablesByOrigin.keys.toList();
    final withStops = ids
        .map(stopById)
        .whereType<NetworkStop>()
        .toList()
      ..sort((a, b) {
        final aCount = _timetablesByOrigin[a.id]?.length ?? 0;
        final bCount = _timetablesByOrigin[b.id]?.length ?? 0;
        final byCount = bCount.compareTo(aCount);
        if (byCount != 0) return byCount;
        return a.city.compareTo(b.city);
      });
    return withStops;
  }

  /// Substring search across stop name, city, depot, and district.
  ///
  /// Ranked so that a prefix match on the city beats a mid-string match on the
  /// depot, and a district stand beats a village stop at equal relevance.
  List<NetworkStop> searchStops(String query, {int limit = 20}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final sorted = stops.toList()
        ..sort((a, b) {
          final byTier = b.tier.compareTo(a.tier);
          if (byTier != 0) return byTier;
          return a.city.compareTo(b.city);
        });
      return sorted.take(limit).toList();
    }

    final scored = <({NetworkStop stop, int score})>[];
    for (final stop in stops) {
      final city = stop.city.toLowerCase();
      final name = stop.name.toLowerCase();
      var score = 0;

      if (city == q) {
        score = 100;
      } else if (city.startsWith(q)) {
        score = 85;
      } else if (name.startsWith(q)) {
        score = 75;
      } else if (city.contains(q)) {
        score = 55;
      } else if (name.contains(q)) {
        score = 45;
      } else if (stop.searchHaystack.contains(q)) {
        score = 25;
      }

      if (score > 0) scored.add((stop: stop, score: score + stop.tier * 3));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.stop.city.compareTo(b.stop.city);
    });
    return scored.take(limit).map((e) => e.stop).toList();
  }

  factory TransitNetwork.fromJson(Map<String, dynamic> json) {
    final classes = (json['service_classes'] as List<dynamic>? ?? const [])
        .map((e) => ServiceClass.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    ServiceClassCatalog.register(classes);

    return TransitNetwork(
      version: (json['version'] as num?)?.toInt() ?? 0,
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
      operatorName: json['operator'] as String? ?? 'MSRTC',
      stops: (json['stops'] as List<dynamic>? ?? const [])
          .map((e) => NetworkStop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      routes: (json['routes'] as List<dynamic>? ?? const [])
          .map((e) => TransitRoute.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      services: (json['services'] as List<dynamic>? ?? const [])
          .map((e) => TransitService.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      timetables: (json['timetables'] as List<dynamic>? ?? const [])
          .map((e) => TimetableRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
