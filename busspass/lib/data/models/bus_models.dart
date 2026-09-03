import 'package:cloud_firestore/cloud_firestore.dart';

class BusStop {
  final String id;
  final String name;
  final String city;
  final String depot;
  final double lat;
  final double lng;

  const BusStop({
    required this.id,
    required this.name,
    required this.city,
    required this.depot,
    required this.lat,
    required this.lng,
  });

  factory BusStop.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BusStop(
      id: doc.id,
      name: data['name'] ?? '',
      city: data['city'] ?? '',
      depot: data['depot'] ?? '',
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'city': city,
        'depot': depot,
        'lat': lat,
        'lng': lng,
      };
}

class BusRoute {
  final String id;
  final String name;
  final String originStopId;
  final String destinationStopId;
  final String originCity;
  final String destinationCity;
  final int distanceKm;
  final String durationHrs;
  final int fareMin;
  final int fareMax;
  final List<String> busTypes;
  final List<String> viaStops;
  final String firstBus;
  final String lastBus;

  const BusRoute({
    required this.id,
    required this.name,
    required this.originStopId,
    required this.destinationStopId,
    required this.originCity,
    required this.destinationCity,
    required this.distanceKm,
    required this.durationHrs,
    required this.fareMin,
    required this.fareMax,
    required this.busTypes,
    required this.viaStops,
    required this.firstBus,
    required this.lastBus,
  });

  factory BusRoute.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BusRoute(
      id: doc.id,
      name: data['name'] ?? '',
      originStopId: data['origin_stop_id'] ?? '',
      destinationStopId: data['destination_stop_id'] ?? '',
      originCity: data['origin_city'] ?? '',
      destinationCity: data['destination_city'] ?? '',
      distanceKm: (data['distance_km'] as num?)?.toInt() ?? 0,
      durationHrs: data['duration_hrs'] ?? '',
      fareMin: (data['fare_min'] as num?)?.toInt() ?? 0,
      fareMax: (data['fare_max'] as num?)?.toInt() ?? 0,
      busTypes: List<String>.from(data['bus_types'] ?? []),
      viaStops: List<String>.from(data['via_stops'] ?? []),
      firstBus: data['first_bus'] ?? '',
      lastBus: data['last_bus'] ?? '',
    );
  }
}
