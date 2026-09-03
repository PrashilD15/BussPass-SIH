import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:busspass/data/models/bus_models.dart';

class BusStopRepository {
  final FirebaseFirestore _firestore;

  BusStopRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetch all bus stops (paginated for large datasets)
  Future<List<BusStop>> getAllStops() async {
    final snapshot = await _firestore.collection('bus_stops').limit(200).get();
    return snapshot.docs.map((doc) => BusStop.fromFirestore(doc)).toList();
  }

  /// Fetch bus stops for a specific city
  Future<List<BusStop>> getStopsByCity(String city) async {
    final snapshot = await _firestore
        .collection('bus_stops')
        .where('city', isEqualTo: city)
        .get();
    return snapshot.docs.map((doc) => BusStop.fromFirestore(doc)).toList();
  }

  /// Search routes by origin and destination city
  Future<List<BusRoute>> searchRoutes(String originCity, String destCity) async {
    final snapshot = await _firestore
        .collection('routes')
        .where('origin_city', isEqualTo: originCity)
        .where('destination_city', isEqualTo: destCity)
        .get();
    return snapshot.docs.map((doc) => BusRoute.fromFirestore(doc)).toList();
  }

  /// Get all routes (for map display)
  Future<List<BusRoute>> getAllRoutes() async {
    final snapshot = await _firestore.collection('routes').limit(100).get();
    return snapshot.docs.map((doc) => BusRoute.fromFirestore(doc)).toList();
  }
}
