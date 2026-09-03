import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/data/models/bus_models.dart';

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// All routes — used by the search logic.
final allRoutesProvider = FutureProvider<List<BusRoute>>((ref) async {
  final firestore = ref.watch(firebaseFirestoreProvider);
  final snapshot = await firestore.collection('routes').get();
  return snapshot.docs.map((doc) => BusRoute.fromFirestore(doc)).toList();
});

/// Returns **all** matching routes between two cities (not just the first).
/// Ordered cheapest-fare first so the UI can show them as selectable cards.
final routeSearchProvider =
    FutureProvider.family<List<BusRoute>, String>((ref, query) async {
  final allRoutes = await ref.watch(allRoutesProvider.future);
  final parts = query.split('|');
  final originCity = parts.isNotEmpty ? parts[0] : '';
  final destCity = parts.length > 1 ? parts[1] : '';

  // Forward match
  final forward = allRoutes
      .where((r) =>
          r.originCity.toLowerCase() == originCity.toLowerCase() &&
          r.destinationCity.toLowerCase() == destCity.toLowerCase())
      .toList();

  if (forward.isNotEmpty) {
    forward.sort((a, b) => a.fareMin.compareTo(b.fareMin));
    return forward;
  }

  // Reverse match
  final reverse = allRoutes
      .where((r) =>
          r.originCity.toLowerCase() == destCity.toLowerCase() &&
          r.destinationCity.toLowerCase() == originCity.toLowerCase())
      .toList();

  reverse.sort((a, b) => a.fareMin.compareTo(b.fareMin));
  return reverse;
});

/// Look up bus stops by their city name — used to resolve via-stop
/// coordinates so the polyline can follow the actual road.
final stopsByCityProvider =
    FutureProvider.family<List<BusStop>, String>((ref, city) async {
  final firestore = ref.watch(firebaseFirestoreProvider);
  final snapshot = await firestore
      .collection('bus_stops')
      .where('city', isEqualTo: city)
      .get();
  return snapshot.docs.map((doc) => BusStop.fromFirestore(doc)).toList();
});
