import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/providers/directions_provider.dart';
import 'package:busspass/core/theme/map_style.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// Live map tracking for the currently-travelled leg of an itinerary.
class LiveNavigationScreen extends ConsumerStatefulWidget {
  final Itinerary itinerary;
  final int legIndex;

  const LiveNavigationScreen({
    super.key,
    required this.itinerary,
    required this.legIndex,
  });

  @override
  ConsumerState<LiveNavigationScreen> createState() =>
      _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends ConsumerState<LiveNavigationScreen> {
  bool _isAlarmOn = false;

  JourneyLeg get _leg => widget.itinerary.legs[widget.legIndex];

  /// The leg geometry as a stable, cacheable [TransLegRef] key.
  TransLegRef get _legRef {
    final leg = _leg;
    final via = leg.intermediateStops
        .map((s) => LatLng(s.lat, s.lng))
        .toList(growable: false);
    return TransLegRef(
      origin: LatLng(leg.boardStop.lat, leg.boardStop.lng),
      via: via,
      destination: LatLng(leg.alightStop.lat, leg.alightStop.lng),
    );
  }

  List<LatLng> get _straightPoints => _legRef.points;

  /// The road-snapped polyline, falling back to the straight stop chain.
  List<LatLng> _points(List<LatLng>? road) =>
      (road?.isNotEmpty ?? false) ? road! : _straightPoints;

  @override
  Widget build(BuildContext context) {
    final leg = _leg;
    final road = ref.watch(legRoadPolylineViewProvider(_legRef));
    final points = _points(road);

    final alightName = leg.alightStop.name.isEmpty
        ? leg.alightStop.city
        : leg.alightStop.name;
    final nextStopName = _nextStopName();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          // ── Live Map ──────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: points.last,
              zoom: 14,
            ),
            style: kModernMapStyleJson,
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            polylines: {
              Polyline(
                polylineId: const PolylineId('route-sheen'),
                points: points,
                color: Colors.white.withValues(alpha: 0.65),
                width: 9,
                jointType: JointType.round,
              ),
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: AppColors.brand,
                width: 5,
                jointType: JointType.round,
              ),
            },
            markers: {
              ..._viaMarkers(),
              Marker(
                markerId: const MarkerId('dest'),
                position: points.last,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
              ),
            },
          ),

          // ── Top Bar ──────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  _TopBarCircle(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.ink,
                        size: 22,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true))
                            .fadeOut(duration: 800.ms),
                        const SizedBox(width: AppSpacing.sm),
                        const Text(
                          'Live Sync',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom Dashboard ──────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 40),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXl)),
                border: Border(
                  top: BorderSide(color: AppColors.hairline),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Progress Bar ────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        leg.boardStop.city,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                            ),
                      ),
                      Text(
                        leg.alightStop.city,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.35,
                      backgroundColor: AppColors.hairline,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.brand),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Next Stop ──────────────────────────────────
                  Text(
                    'NEXT STOP',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.inkMuted,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    nextStopName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 24,
                        ),
                  ),

                  const Divider(height: 40, color: AppColors.hairline),

                  // ── Destination Info & Alarm ────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DESTINATION',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: AppColors.inkMuted,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              alightName,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ETA: ${Schedule.formatClock(Schedule.minuteOfDay(leg.arrivesAt))}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isAlarmOn = !_isAlarmOn);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isAlarmOn
                                  ? 'Wake-up alarm set for 5 mins before arrival!'
                                  : 'Wake-up alarm disabled.'),
                              backgroundColor: AppColors.ink,
                            ),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: _isAlarmOn
                                ? AppColors.brand
                                : AppColors.canvas,
                            borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd),
                            border: Border.all(
                              color: _isAlarmOn
                                  ? AppColors.brand
                                  : AppColors.hairline,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isAlarmOn
                                    ? Icons.alarm_on_rounded
                                    : Icons.alarm_off_rounded,
                                color: _isAlarmOn
                                    ? Colors.white
                                    : AppColors.inkMuted,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Alarm',
                                style: TextStyle(
                                  color: _isAlarmOn
                                      ? Colors.white
                                      : AppColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
                .animate()
                .slideY(
                    begin: 1.0,
                    duration: 500.ms,
                    curve: Curves.easeOutCubic),
          ),
        ],
      ),
    );
  }

  /// Orange markers for intermediate stops passed between board and alight.
  Set<Marker> _viaMarkers() {
    final leg = _leg;
    final stops = leg.intermediateStops;
    if (stops.isEmpty) return const {};
    return stops
        .map((s) => Marker(
              markerId: MarkerId('via-${leg.route.id}-${s.stopId}'),
              position: LatLng(s.lat, s.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange),
            ))
        .toSet();
  }

  String _nextStopName() {
    final leg = _leg;
    if (leg.intermediateStops.isNotEmpty) {
      final s = leg.intermediateStops.first;
      return s.name.isEmpty ? s.city : s.name;
    }
    return leg.alightStop.name.isEmpty
        ? leg.alightStop.city
        : leg.alightStop.name;
  }
}

class _TopBarCircle extends StatelessWidget {
  final Widget child;

  const _TopBarCircle({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
