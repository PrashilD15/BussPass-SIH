import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/data/models/bus_models.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

class LiveNavigationScreen extends StatefulWidget {
  final BusStop destination;

  const LiveNavigationScreen({super.key, required this.destination});

  @override
  State<LiveNavigationScreen> createState() =>
      _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen> {
  final LatLng _mockCurrentLoc =
      const LatLng(18.5300, 73.8500);
  late LatLng _mockDest;
  bool _isAlarmOn = false;

  @override
  void initState() {
    super.initState();
    _mockDest = LatLng(widget.destination.lat, widget.destination.lng);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          // ── Live Map ──────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _mockCurrentLoc,
              zoom: 14,
            ),
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: [_mockCurrentLoc, _mockDest],
                color: AppColors.brand,
                width: 5,
              )
            },
            markers: {
              Marker(
                markerId: const MarkerId('dest'),
                position: _mockDest,
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
                        'Origin',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                ),
                      ),
                      Text(
                        widget.destination.city,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    'NEXT STOP IN 4 MINS',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.inkMuted,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Lonavala Toll Plaza',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 24,
                            ),
                  ),

                  const Divider(
                      height: 40, color: AppColors.hairline),

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
                              widget.destination.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ETA: 11:10 AM',
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