import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/data/models/bus_models.dart';
import 'package:busspass/features/journey/presentation/live_navigation_screen.dart';
import 'package:busspass/data/providers/route_provider.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class JourneyDetailsScreen extends ConsumerStatefulWidget {
  final BusStop origin;
  final BusStop destination;

  const JourneyDetailsScreen({
    super.key,
    required this.origin,
    required this.destination,
  });

  @override
  ConsumerState<JourneyDetailsScreen> createState() =>
      _JourneyDetailsScreenState();
}

class _JourneyDetailsScreenState extends ConsumerState<JourneyDetailsScreen> {
  late BusStop _origin;
  late BusStop _dest;
  int _selectedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _origin = widget.origin;
    _dest = widget.destination;
  }

  void _showBoardingDialog(BusRoute route) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.brandLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                size: 28,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Are you in the bus?',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We will start syncing your GPS to track the\njourney on ${route.name}.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              label: 'Yes, I am onboard',
              icon: Icons.check_rounded,
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveNavigationScreen(
                        destination: widget.destination),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveNavigationScreen(
                          destination: widget.destination),
                    ),
                  );
                },
                child: const Text(
                  'No, navigate to bus stop',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routesAsync = ref.watch(
        routeSearchProvider('${_origin.city}|${_dest.city}'));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: routesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand),
        ),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (routes) {
          if (routes.isEmpty) {
            return _NoRouteFound(
              originCity: _origin.city,
              destCity: _dest.city,
            );
          }

          final route = routes[_selectedRouteIndex.clamp(0, routes.length - 1)];

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // ── Map Header ──────────────────────────────────
                  SliverAppBar(
                    expandedHeight: 280,
                    pinned: true,
                    backgroundColor: AppColors.brand,
                    leading: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.ink, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: _RouteMap(
                        origin: _origin,
                        destination: _dest,
                        route: route,
                      ),
                    ),
                  ),

                  // ── Overview Stats ───────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                      child: AppCard(
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              label: 'Total Fare',
                              value: '\u20b9${route.fareMin}',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                            Container(
                                width: 1,
                                height: 40,
                                color: AppColors.hairline),
                            _StatItem(
                              label: 'Est. Time',
                              value: route.durationHrs,
                              icon: Icons.timer_outlined,
                            ),
                            Container(
                                width: 1,
                                height: 40,
                                color: AppColors.hairline),
                            _StatItem(
                              label: 'Distance',
                              value: '${route.distanceKm} km',
                              icon: Icons.map_outlined,
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .slideY(
                              begin: 0.15,
                              duration: 500.ms,
                              curve: Curves.easeOutCubic),
                    ),
                  ),

                  // ── Bus Type Cards (if multiple routes) ─────────
                  if (routes.length > 1)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Routes',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 19),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ...List.generate(routes.length, (i) {
                              final r = routes[i];
                              final isSelected = i == _selectedRouteIndex;
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: _BusTypeCard(
                                  route: r,
                                  isSelected: isSelected,
                                  onTap: () => setState(
                                      () => _selectedRouteIndex = i),
                                ),
                              );
                            }),
                          ],
                        ),
                          )
                              .animate()
                              .fadeIn(delay: 200.ms),
                    ),

                  // ── Schedule Info ───────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                _ScheduleItem(
                                  icon: Icons.wb_sunny_outlined,
                                  label: 'First Bus',
                                  time: route.firstBus,
                                ),
                                const SizedBox(width: AppSpacing.xl),
                                _ScheduleItem(
                                  icon: Icons.nightlight_outlined,
                                  label: 'Last Bus',
                                  time: route.lastBus,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                TagChip(
                                  icon: Icons.directions_bus_outlined,
                                  label:
                                      '${route.busTypes.length} bus types',
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                TagChip(
                                  icon: Icons.stop_circle_outlined,
                                  label:
                                      '${route.viaStops.length} via stops',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Fare Range by Bus Type ──────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fare by Bus Type',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            ...route.busTypes.map((type) {
                              final fare = _estimateFare(
                                  type, route.fareMin, route.fareMax);
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.brandLight,
                                        borderRadius:
                                            BorderRadius.circular(
                                                AppSpacing.radiusSm),
                                      ),
                                      child: Icon(
                                        type.contains('AC')
                                            ? Icons.ac_unit_outlined
                                            : Icons.directions_bus_outlined,
                                        color: AppColors.brand,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            type,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(fontSize: 14),
                                          ),
                                          Text(
                                            type.contains('AC')
                                                ? 'Air-conditioned, comfortable seats'
                                                : type.contains('Sleeper')
                                                    ? 'Sleeper berths for overnight'
                                                    : type.contains('Ordinary')
                                                        ? 'Basic seating, all stops'
                                                        : 'Reclining seats, limited stops',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '\u20b9$fare',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontSize: 16,
                                              color: AppColors.brand),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Timeline Itinerary ──────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                      child: Text(
                        'Route Itinerary',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontSize: 19),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final timeline = _buildTimeline(route, _origin, _dest);
                          final item = timeline[index];
                          final isLast = index == timeline.length - 1;

                          return Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              // Time column
                              SizedBox(
                                width: 56,
                                child: Text(
                                  item['time'] as String,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontSize: 11),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.lg),

                              // Timeline dot + line
                              Column(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _dotColor(item['type'] as String),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _dotBorderColor(item['type'] as String),
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Container(
                                      width: 1.5,
                                      height: 56,
                                      color: AppColors.hairline,
                                    ),
                                ],
                              ),
                              const SizedBox(width: AppSpacing.lg),

                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(fontSize: 15),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item['subtitle'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (item.containsKey('tag')) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      TagChip(
                                        label: item['tag'] as String,
                                      ),
                                    ],
                                    const SizedBox(
                                        height: AppSpacing.xl),
                                  ],
                                ),
                              ),
                            ],
                          )
                              .animate()
                              .fadeIn(
                                  duration: 400.ms,
                                  delay: (index * 80).ms)
                              .slideX(begin: 0.06);
                        },
                        childCount: _buildTimeline(route, _origin, _dest).length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 120)),
                ],
              ),

              // ── Start Journey Button ────────────────────────────
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: PrimaryButton(
                  label: 'Start Journey',
                  icon: Icons.directions_bus_rounded,
                  onPressed: () => _showBoardingDialog(route),
                )
                    .animate()
                    .slideY(
                        begin: 1.0,
                        duration: 600.ms,
                        delay: 300.ms,
                        curve: Curves.easeOutCubic),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build a real timeline from route data.
  List<Map<String, String>> _buildTimeline(
      BusRoute route, BusStop origin, BusStop dest) {
    final items = <Map<String, String>>[];

    // 1. Walk to origin
    items.add({
      'title': 'Depart from ${origin.name}',
      'subtitle': '${origin.city} \u2022 ${origin.depot}',
      'time': route.firstBus,
      'type': 'origin',
    });

    // 2. Board
    final busType =
        route.busTypes.isNotEmpty ? route.busTypes.first : route.name;
    items.add({
      'title': 'Board: $busType',
      'subtitle':
          '${route.originCity} \u2022 ${route.distanceKm} km \u2022 ${route.durationHrs}',
      'time': route.firstBus,
      'type': 'board',
      'tag': 'Fare: \u20b9${route.fareMin} \u2013 ${route.fareMax}',
    });

    // 3. Via stops
    if (route.viaStops.isNotEmpty) {
      items.add({
        'title': '${route.viaStops.length} stops en route',
        'subtitle': route.viaStops.join(' \u2022 '),
        'time': '',
        'type': 'transit',
      });
    }

    // 4. Arrive
    items.add({
      'title': 'Arrive at ${dest.name}',
      'subtitle': '${dest.city} \u2022 ${dest.depot}',
      'time': 'ETA',
      'type': 'dest',
      'tag': 'Fare: \u20b9${route.fareMin} \u2013 ${route.fareMax}',
    });

    return items;
  }

  Color _dotColor(String type) {
    switch (type) {
      case 'origin':
        return AppColors.brand;
      case 'board':
        return AppColors.accent;
      case 'transit':
        return AppColors.surface;
      case 'dest':
        return AppColors.brand;
      default:
        return AppColors.brand;
    }
  }

  Color _dotBorderColor(String type) {
    switch (type) {
      case 'origin':
        return AppColors.brand;
      case 'board':
        return AppColors.accent;
      case 'transit':
        return AppColors.hairline;
      case 'dest':
        return AppColors.brand;
      default:
        return AppColors.brand;
    }
  }

  /// Rough fare estimate by bus type.  The data only stores a min/max
  /// range — this spreads them across types roughly.
  int _estimateFare(String type, int fareMin, int fareMax) {
    if (type.contains('Ordinary')) return fareMin;
    if (type.contains('AC') || type.contains('Sleeper')) return fareMax;
    // Semi Luxury / Shivshahi / Shivneri — middle
    return ((fareMin + fareMax) / 2).round();
  }
}

// ── Map Widget ───────────────────────────────────────────────────────────────
class _RouteMap extends StatelessWidget {
  final BusStop origin;
  final BusStop destination;
  final BusRoute route;

  const _RouteMap({
    required this.origin,
    required this.destination,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final points = _routePoints();
    final centerLat = points.map((p) => p.latitude).reduce((a, b) => a + b) /
        points.length;
    final centerLng = points.map((p) => p.longitude).reduce((a, b) => a + b) /
        points.length;

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(centerLat, centerLng),
        zoom: points.length > 2 ? 6.5 : 7.5,
      ),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      polylines: {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: AppColors.brand,
          width: 4,
        ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(origin.lat, origin.lng),
          infoWindow: InfoWindow(title: origin.name, snippet: origin.city),
        ),
        Marker(
          markerId: const MarkerId('dest'),
          position: LatLng(destination.lat, destination.lng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow:
              InfoWindow(title: destination.name, snippet: destination.city),
        ),
        // Via stop markers
        ...route.viaStops.asMap().entries.map((entry) {
          // We can only show named via-stops — their coordinates aren't in
          // the route document so we skip unknown ones.
          return <Marker>{};
        }).expand((s) => s),
      },
    );
  }

  /// Build polyline points from origin → via stops → destination.
  List<LatLng> _routePoints() {
    // Since via_stops are just city names (strings) in the seed data,
    // we can't resolve their exact lat/lng without a lookup.  We build
    // a best-effort polyline with what we have.
    final points = <LatLng>[
      LatLng(origin.lat, origin.lng),
    ];

    // Add destination
    points.add(LatLng(destination.lat, destination.lng));

    return points;
  }
}

// ── Stat Item ────────────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.brand, size: 22),
        const SizedBox(height: AppSpacing.sm),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 17)),
        const SizedBox(height: 2),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12)),
      ],
    );
  }
}

// ── Bus Type Card ────────────────────────────────────────────────────────────
class _BusTypeCard extends StatelessWidget {
  final BusRoute route;
  final bool isSelected;
  final VoidCallback onTap;

  const _BusTypeCard({
    required this.route,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.brand : AppColors.hairline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.brand
                    : AppColors.canvas,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.directions_bus_outlined,
                color: isSelected ? Colors.white : AppColors.inkMuted,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${route.busTypes.join(', ')} \u2022 ${route.durationHrs}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '\u20b9${route.fareMin}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    color: AppColors.brand,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Schedule Item ────────────────────────────────────────────────────────────
class _ScheduleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;

  const _ScheduleItem({
    required this.icon,
    required this.label,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, color: AppColors.inkSoft, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                  ),
            ),
            Text(
              time,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── No Route Found ───────────────────────────────────────────────────────────
class _NoRouteFound extends StatelessWidget {
  final String originCity;
  final String destCity;

  const _NoRouteFound({
    required this.originCity,
    required this.destCity,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Icon(
                Icons.bus_alert_rounded,
                size: 32,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'No direct route found',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No buses run directly from $originCity to $destCity.\nTry searching for an intermediate city.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              label: 'Go Back',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}