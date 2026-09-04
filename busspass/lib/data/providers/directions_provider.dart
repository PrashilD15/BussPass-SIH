import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:busspass/core/services/directions_service.dart';

final directionsServiceProvider =
    Provider<DirectionsService>((ref) => DirectionsService());

/// Resolve a **road-snapped** polyline for a leg's travelled portion. Falls
/// back to the straight stop-to-stop points when the API is unavailable.
final legRoadPolylineProvider =
    FutureProvider.family<List<LatLng>, TransLegRef>((ref, leg) async {
  final service = ref.watch(directionsServiceProvider);

  final points = leg.points;
  if (points.length < 2) return <LatLng>[];

  final waypoints = points.length > 2
      ? points.sublist(1, points.length - 1).toList()
      : <LatLng>[];

  final result = await service.route(
    origin: points.first,
    waypoints: waypoints,
    destination: points.last,
  );

  if (result != null && result.points.isNotEmpty) {
    return result.points.map((p) => p.latLng).toList();
  }

  return points;
});

/// Convenience wrapper exposing the resolved road polyline for the UI.
final legRoadPolylineViewProvider =
    Provider.family<List<LatLng>?, TransLegRef>((ref, leg) {
  final async = ref.watch(legRoadPolylineProvider(leg));
  return async.hasValue ? async.value : null;
});

/// Leg geometry as a stable, equatable family key for the road polyline
/// provider. Built from the route stop sequence so the same corridor resolves
/// from cache instead of re-fetching.
class TransLegRef {
  final LatLng origin;
  final List<LatLng> via;
  final LatLng destination;

  const TransLegRef({
    required this.origin,
    required this.via,
    required this.destination,
  });

  List<LatLng> get points => [origin, ...via, destination];

  @override
  bool operator ==(Object other) =>
      other is TransLegRef &&
      other.origin == origin &&
      _listsEqual(other.via, via) &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(origin, via, destination);

  static bool _listsEqual(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
