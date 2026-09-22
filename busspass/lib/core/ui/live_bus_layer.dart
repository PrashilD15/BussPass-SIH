/// Shared live-fleet map overlay.
///
/// Both the map tab and live navigation need the same thing: fleet markers
/// whose fill matches crowd level, rotated to heading, with a hollow centre
/// for simulated reports — and motion that glides between the fleet's coarse
/// position ticks instead of teleporting every 3 seconds.
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/occupancy_engine.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

/// Builds and animates Google Map markers for a live fleet.
///
/// The fleet stream ticks every few seconds; between ticks this layer renders
/// a linear glide from each bus's previous position toward its latest one,
/// so a watch redrawn at ~10 fps makes the bus *move* rather than jump.
class LiveBusLayer {
  LiveBusLayer();

  /// How long the glide between two consecutive fleet ticks should take.
  static const Duration glide = Duration(milliseconds: 2900);

  // Per-bus render state: what the marker shows now, where it came from, and
  // where it is heading.
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};
  final Map<String, DateTime> _since = {};
  final Map<String, double> _headings = {};
  final Map<String, bool> _seenThisTick = {};

  /// Markers for the current frame. Call at ~10 fps while the fleet is live;
  /// positions interpolate toward the most recent reports.
  ///
  /// [onBusTap] receives the bus id when one of its markers is tapped.
  Set<Marker> frame(
    AppPalette palette,
    List<LiveBus> buses, {
    String? selectedId,
    void Function(String busId)? onBusTap,
  }) {
    final now = DateTime.now();

    // Ingest: previous target becomes the new start point, latest report is
    // the new target.
    for (final id in _to.keys) {
      _seenThisTick[id] = false;
    }
    for (final bus in buses) {
      if (bus.state == BusState.offService) continue;
      final position = LatLng(bus.lat, bus.lng);
      final previous = _to[bus.id];
      if (previous != null && previous != position) {
        _from[bus.id] = _currentPosition(bus.id, now) ?? previous;
      } else if (previous == null) {
        _from[bus.id] = position;
      }
      _to[bus.id] = position;
      _since[bus.id] = now;
      _headings[bus.id] = bus.heading;
      _seenThisTick[bus.id] = true;
    }
    // Drop buses that went off-service.
    _from.removeWhere((id, _) => _seenThisTick[id] != true);
    _to.removeWhere((id, _) => _seenThisTick[id] != true);
    _since.removeWhere((id, _) => _seenThisTick[id] != true);
    _headings.removeWhere((id, _) => _seenThisTick[id] != true);

    final markers = <Marker>{};
    for (final bus in buses) {
      if (bus.state == BusState.offService) continue;

      final crowdLevel = _levelFor(bus);
      final fill = palette.forCrowdLevel(crowdLevel.index);
      // The real badge once [BusMarkerBuilder.prefetch] has rendered it; the
      // hue-matched default marker until then. Both are synchronous here
      // because this loop runs at ~10 fps.
      final bitmap = BusMarker.cached(
            fill: fill,
            simulated: bus.isSimulated,
          ) ??
          BusMarkerPlaceholder.descriptor(fill, bus.isSimulated);

      final position = _currentPosition(bus.id, now) ??
          LatLng(bus.lat, bus.lng);
      final rotation = _headings[bus.id] ?? 0;

      markers.add(Marker(
        markerId: MarkerId('bus_${bus.id}'),
        position: position,
        icon: bitmap,
        anchor: const Offset(0.5, 0.5),
        // Heading-rotated and flat so the badge points where the bus travels
        // regardless of camera bearing.
        rotation: rotation,
        flat: true,
        zIndexInt: bus.id == selectedId ? 10 : 5,
        consumeTapEvents: true,
        onTap: onBusTap == null ? null : () => onBusTap(bus.id),
      ));
    }
    return markers;
  }

  CrowdLevel _levelFor(LiveBus bus) {
    final serviceClass = ServiceClassCatalog.byKey(bus.busType);
    if (bus.passengerCount != null) {
      return OccupancyEngine.fromReported(
        passengerCount: bus.passengerCount!,
        serviceClass: serviceClass,
      ).level;
    }
    return OccupancyEngine.model(
      serviceClass: serviceClass,
      at: DateTime.now(),
    ).level;
  }

  LatLng? _currentPosition(String id, DateTime now) {
    final from = _from[id];
    final to = _to[id];
    final since = _since[id];
    if (from == null || to == null || since == null) return to;
    final t =
        now.difference(since).inMilliseconds / glide.inMilliseconds;
    if (t >= 1) return to;
    if (t <= 0) return from;
    final e = Curves.linear.transform(t);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * e,
      from.longitude + (to.longitude - from.longitude) * e,
    );
  }

  void dispose() {
    _from.clear();
    _to.clear();
    _since.clear();
    _headings.clear();
  }
}

/// Placeholder descriptor used until the async-rendered [BusMarker] bitmap is
/// cached. `frame()` runs on a 10 fps ticker, so it must be synchronous — the
/// real bitmaps are pre-generated by [BusMarkerBuilder.prefetch] when the
/// fleet first arrives, and any still-missing key falls back to this.
class BusMarkerPlaceholder {
  BusMarkerPlaceholder._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static BitmapDescriptor descriptor(Color fill, bool simulated) {
    final key = '${fill.toARGB32()}_$simulated';
    return _cache[key] ??= BitmapDescriptor.defaultMarkerWithHue(
      simulated
          ? BitmapDescriptor.hueAzure
          : _hueFor(fill),
    );
  }

  static double _hueFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    // clamp into a valid marker hue range; default markers only take 0–360.
    return hsl.hue.clamp(0.0, 360.0);
  }
}

/// Pre-generates the real [BusMarker] bitmaps for the set of (crowd colour,
/// simulated) pairs so `frame()` never falls back to the placeholder.
class BusMarkerBuilder {
  BusMarkerBuilder._();

  static Future<void> prefetch(AppPalette palette) async {
    for (var level = 0; level <= 4; level++) {
      final color = palette.forCrowdLevel(level);
      await BusMarker.create(fill: color, simulated: false);
      await BusMarker.create(fill: color, simulated: true);
    }
  }
}

/// Smoothly animates a camera to follow a bus.
void animateCameraToBus(
  GoogleMapController? controller,
  LiveBus bus, {
  double zoom = 15,
  Duration duration = const Duration(milliseconds: 1500),
}) {
  if (controller == null) return;
  controller.animateCamera(
    CameraUpdate.newLatLngZoom(LatLng(bus.lat, bus.lng), zoom),
    duration: duration,
  );
}

/// The bearing from a bus's current position toward its next stop on a route,
/// used to orient the marker when the reported heading is stale or zero.
double busTravelBearing(LiveBus bus, List<GeoPoint> polyline) {
  if (bus.heading > 0.5) return bus.heading;
  if (polyline.length < 2) return 0;
  final here = GeoPoint(bus.lat, bus.lng);
  final projected = Geo.projectOnPolyline(here, polyline);
  if (projected == null) return 0;
  final aheadIdx = (projected.segmentIndex + 1).clamp(0, polyline.length - 1);
  return Geo.bearing(here, polyline[aheadIdx]);
}
