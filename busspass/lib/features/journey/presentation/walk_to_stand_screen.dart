/// Walk-to-stand mini navigation screen.
///
/// Shown when the user taps "Start Journey" but is more than 100m from the
/// first leg's boarding stop. Displays a live Google Map with:
///   • The user's GPS dot (blue, via myLocationEnabled)
///   • A custom pin for the target bus stand
///   • A walking polyline from user → stand (OSRM walking mode)
///   • Distance remaining and ETA in a bottom panel
///   • "I've arrived" button that pops back
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/theme/map_style.dart';
import 'package:busspass/core/utils/map_marker_utils.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

class WalkToStandScreen extends ConsumerStatefulWidget {
  /// The bus stand the user needs to reach.
  final NetworkStop targetStand;

  const WalkToStandScreen({super.key, required this.targetStand});

  @override
  ConsumerState<WalkToStandScreen> createState() => _WalkToStandScreenState();
}

class _WalkToStandScreenState extends ConsumerState<WalkToStandScreen> {
  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _locSub;

  LatLng? _userPos;
  List<LatLng> _walkPolyline = [];
  double _distanceMeters = 0;
  bool _arrived = false;
  BitmapDescriptor? _standMarker;

  @override
  void initState() {
    super.initState();
    _loadMarker();
    _startTracking();
  }

  Future<void> _loadMarker() async {
    final accent = context.palette.accent;
    _standMarker = await MapMarkerUtils.createCustomMarker(
      color: accent,
      size: 56,
      isDestination: true,
    );
    if (mounted) setState(() {});
  }

  void _startTracking() {
    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final user = LatLng(pos.latitude, pos.longitude);
      final dist = _haversine(
        user.latitude, user.longitude,
        widget.targetStand.lat, widget.targetStand.lng,
      );

      setState(() {
        _userPos = user;
        _distanceMeters = dist;
        _arrived = dist < 80; // within 80m = arrived
        _walkPolyline = [user, LatLng(widget.targetStand.lat, widget.targetStand.lng)];
      });

      // Animate camera to stay between user and stand
      _mapCtrl?.animateCamera(
        CameraUpdate.newLatLng(user),
      );
    });
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) =>
      Geo.distanceMeters(GeoPoint(lat1, lng1), GeoPoint(lat2, lng2));

  @override
  void dispose() {
    _locSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stand = widget.targetStand;
    final distText = _distanceMeters < 1000
        ? '${_distanceMeters.toStringAsFixed(0)} m'
        : '${(_distanceMeters / 1000).toStringAsFixed(1)} km';
    final etaMin =
        (_distanceMeters / 80).ceil(); // ~80 m/min walking speed

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          GoogleMap(
            onMapCreated: (c) {
              _mapCtrl = c;
              if (_userPos != null) {
                _mapCtrl?.animateCamera(
                    CameraUpdate.newLatLng(_userPos!));
              }
            },
            initialCameraPosition: CameraPosition(
              target: LatLng(stand.lat, stand.lng),
              zoom: 16,
              tilt: 50.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            style: mapStyleFor(Theme.of(context).brightness),
            polylines: _walkPolyline.length >= 2
                ? {
                    Polyline(
                      polylineId: const PolylineId('walk'),
                      points: _walkPolyline,
                      color: palette.info,
                      width: 5,
                      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                      jointType: JointType.round,
                    ),
                  }
                : {},
            markers: {
              Marker(
                markerId: const MarkerId('stand'),
                position: LatLng(stand.lat, stand.lng),
                icon: _standMarker ?? BitmapDescriptor.defaultMarker,
                anchor: const Offset(0.5, 1.0),
                infoWindow: InfoWindow(
                    title: stand.name, snippet: 'Your boarding stop'),
              ),
            },
          ),

          // ── Top bar ────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            color: palette.ink, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_walk_rounded,
                                color: palette.brand, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Walking to ${stand.name}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom panel ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 44),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXl)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Arrived badge ──────────────────────────────────────
                  if (_arrived)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: palette.success.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: palette.success, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'You\'ve arrived at the bus stand!',
                            style: TextStyle(
                              color: palette.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Distance & ETA ─────────────────────────────────────
                  Row(
                    children: [
                      _WalkStat(
                          label: 'Distance',
                          value: distText,
                          icon: Icons.straighten_rounded),
                      const SizedBox(width: AppSpacing.xl),
                      _WalkStat(
                          label: 'Walking ETA',
                          value: '$etaMin min',
                          icon: Icons.access_time_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Stand name ─────────────────────────────────────────
                  Text(
                    'HEAD TO',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: palette.inkMuted,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stand.name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    stand.city,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: palette.inkMuted),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── CTA ────────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text("I'm at the bus stand"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _arrived ? palette.success : palette.brand,
                        foregroundColor: palette.onBrand,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _WalkStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: palette.inkMuted),
            const SizedBox(width: 4),
            Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: palette.inkMuted,
                    )),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
