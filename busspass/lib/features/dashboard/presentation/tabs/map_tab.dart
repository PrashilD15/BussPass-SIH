/// The live map tab: stops *and* the running fleet, one honest picture.
///
/// Previously this tab drew stop markers over an unstyled map, with a booking
/// card whose rows were invented ("Mumbai Central / Recently visited") and a
/// "Find Routes from here" button that discarded the selected stop. Now the
/// fleet streams through [LiveBusLayer] with gliding markers, tapping a bus
/// opens its real next-stop ETAs, and stop selection carries through to the
/// journey search.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:busspass/core/math/eta_engine.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/occupancy_engine.dart';
import 'package:busspass/core/theme/map_style.dart';
import 'package:busspass/core/ui/live_bus_layer.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/providers/map_provider.dart';
import 'package:busspass/features/journey/presentation/journey_search_screen.dart';
import 'package:busspass/features/journey/presentation/live_navigation_screen.dart';
import 'package:busspass/features/journey/presentation/tracking_itinerary.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  GoogleMapController? _mapController;
  NetworkStop? _selectedStop;
  LiveBus? _selectedBus;

  final LiveBusLayer _busLayer = LiveBusLayer();
  List<LiveBus> _fleet = const [];
  AppPalette? _palette;
  Timer? _ticker;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _prefetchRequested = false;
  bool _tickerEnabled = true;

  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(18.5204, 73.8567),
    zoom: 12,
    tilt: 50.0,
  );

  @override
  void initState() {
    super.initState();
    // ~10 fps redraw while a fleet is on screen; the layer glides positions
    // between the fleet's coarse ticks. IndexedStack disables tickers for
    // hidden tabs, so the redraw pauses when the map isn't visible.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_fleet.isNotEmpty && _palette != null && _tickerEnabled) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerMode();
    _applyMapStyle();
  }

  void _syncTickerMode() {
    // Follow the dashboard's IndexedStack TickerMode flips via its notifier —
    // tab switches don't run didChangeDependencies on hidden children.
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerModeChanged);
      _tickerMode = notifier;
      _tickerMode?.addListener(_onTickerModeChanged);
      _tickerEnabled = _tickerMode!.value.enabled;
    }
  }

  void _onTickerModeChanged() {
    if (mounted) setState(() => _tickerEnabled = _tickerMode!.value.enabled);
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onTickerModeChanged);
    _ticker?.cancel();
    _busLayer.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    ref.read(userLocationProvider.future).then((position) {
      if (position != null && mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 13,
              tilt: 50.0,
            ),
          ),
        );
      }
    });
  }

  void _applyMapStyle() {
    // The `style:` argument applies only at creation; re-apply on every
    // brightness flip while the map is alive (deprecated but the only API
    // for live restyling in google_maps_flutter 2.x).
    // ignore: deprecated_member_use
    _mapController?.setMapStyle(
      mapStyleFor(Theme.of(context).brightness),
    );
  }

  Set<Marker> _buildStopMarkers(List<StopTapTarget> targets) => {
        for (final target in targets)
          target.marker.copyWith(
            consumeTapEventsParam: true,
            onTapParam: () => setState(() {
              _selectedBus = null;
              _selectedStop = target.stop;
            }),
          ),
      };

  void _openBusSheet(LiveBus bus) {
    setState(() {
      _selectedStop = null;
      _selectedBus = bus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    _palette = palette;

    final markersAsync = ref.watch(busStopTargetsProvider);
    final fleetAsync = ref.watch(liveFleetProvider);
    final fleet = fleetAsync.value ?? LiveFleet.empty;
    _fleet = fleet.buses;

    // Pre-render the real badge bitmaps once per palette, so the 10 fps glide
    // loop only ever reads from the synchronous cache. The future result
    // replaces the placeholder descriptors in BusMarker's shared cache.
    if (_fleet.isNotEmpty && !_prefetchRequested) {
      _prefetchRequested = true;
      BusMarkerBuilder.prefetch(palette).then((_) {
        if (mounted) setState(() {});
      });
    }

    final busMarkers = _fleet.isEmpty
        ? const <Marker>{}
        : _busLayer.frame(
            palette,
            _fleet,
            selectedId: _selectedBus?.id,
            onBusTap: (busId) {
              final bus = fleet.byId(busId);
              if (bus != null) _openBusSheet(bus);
            },
          );

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: _defaultCamera,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            mapType: MapType.normal,
            style: mapStyleFor(Theme.of(context).brightness),
            markers: {
              ...markersAsync.maybeWhen(
                data: _buildStopMarkers,
                orElse: () => const <Marker>{},
              ),
              ...busMarkers,
              if (_selectedStop != null)
                Marker(
                  markerId: const MarkerId('selected-stop'),
                  position:
                      LatLng(_selectedStop!.lat, _selectedStop!.lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                ),
            },
            onTap: (_) => setState(() {
              _selectedStop = null;
              _selectedBus = null;
            }),
            onCameraMove: (position) {
              ref
                  .read(currentMapZoomProvider.notifier)
                  .setZoom(position.zoom);
            },
          ),

          // ── Provenance header pill ────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: _FleetHeaderPill(fleet: fleet),
                ),
              ),
            ),
          ),

          // ── My Location FAB ──────────────────────────────────────────
          Positioned(
            bottom: (_selectedStop != null || _selectedBus != null) ? 220 : 120,
            right: 16,
            child: _MapFab(
              icon: Icons.my_location_rounded,
              onTap: () async {
                final pos = await ref.read(userLocationProvider.future);
                if (pos != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(pos.latitude, pos.longitude),
                        zoom: 14,
                        tilt: 50.0,
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          // ── Selected bus panel ───────────────────────────────────────
          if (_selectedBus != null)
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: _BusPanel(
                bus: _selectedBus!,
                source: fleet.source,
                onClose: () => setState(() => _selectedBus = null),
              ),
            )
          else if (_selectedStop != null)
            // ── Stop sheet: real departures, real hand-off to search ───
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: _StopBottomSheet(
                stop: _selectedStop!,
                onClose: () => setState(() => _selectedStop = null),
              ),
            )
          else
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: _BookingCard(
                onSearchTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const JourneySearchScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provenance pill
// ─────────────────────────────────────────────────────────────────────────────

class _FleetHeaderPill extends StatelessWidget {
  final LiveFleet fleet;
  const _FleetHeaderPill({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = fleet.buses
        .where((b) => b.state != BusState.offService)
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.92),
        borderRadius: AppSpacing.brPill,
        border: Border.all(color: palette.hairline),
        boxShadow: AppShadow.raised(Colors.black),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProvenanceChip(source: fleet.source),
          if (count > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 1,
              height: 14,
              color: palette.hairline,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count on the road',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: palette.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map FAB
// ─────────────────────────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: palette.surface,
          shape: BoxShape.circle,
          border: Border.all(color: palette.hairline),
          boxShadow: AppShadow.raised(Colors.black),
        ),
        child: Icon(icon, color: palette.brand, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selected bus panel
// ─────────────────────────────────────────────────────────────────────────────

class _BusPanel extends ConsumerStatefulWidget {
  final LiveBus bus;
  final LiveSource source;
  final VoidCallback onClose;

  const _BusPanel({
    required this.bus,
    required this.source,
    required this.onClose,
  });

  @override
  ConsumerState<_BusPanel> createState() => _BusPanelState();
}

class _BusPanelState extends ConsumerState<_BusPanel> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final bus = widget.bus;
    final now = ref.watch(clockProvider);
    final networkAsync = ref.watch(networkProvider);
    final route =
        networkAsync.value?.routeById(bus.routeId);

    final serviceClass = ServiceClassCatalog.byKey(bus.busType);
    final occupancy = bus.passengerCount != null
        ? OccupancyEngine.fromReported(
            passengerCount: bus.passengerCount!,
            serviceClass: serviceClass,
          )
        : OccupancyEngine.model(
            serviceClass: serviceClass,
            at: now,
            journeyFraction: route == null || route.distanceKm <= 0
                ? 0
                : (bus.travelledKm / route.distanceKm).clamp(0.0, 1.0),
          );

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl)),
        boxShadow: AppShadow.floating(Colors.black),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: SkeletonDividerHandle(),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bus.busType,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (route != null)
                        Text(
                          route.name,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                TagChip(
                  label: bus.state.label,
                  dense: true,
                  foreground: bus.state == BusState.inTransit
                      ? palette.success
                      : palette.warning,
                  background: bus.state == BusState.inTransit
                      ? palette.successLight
                      : palette.warningLight,
                ),
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded,
                        color: palette.inkMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OccupancyPill(
                  level: occupancy.level,
                  detail:
                      occupancy.isReported && occupancy.seatsAvailable > 0
                          ? '${occupancy.seatsAvailable} seats free'
                          : null,
                ),
                DelayChip(bus: bus, now: now),
                ProvenanceChip(source: widget.source),
              ],
            ),

            // ── Next stops with live ETAs ────────────────────────────────
            if (route != null && route.stops.length > 2) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('NEXT STOPS',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1)),
              const SizedBox(height: AppSpacing.sm),
              ..._nextStops(route, bus, now, serviceClass)
                  .take(3)
                  .map((entry) => _NextStopRow(
                        name: entry.name,
                        minutes: entry.minutes,
                      )),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Track this bus',
              icon: Icons.my_location_rounded,
              onPressed: route == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveNavigationScreen(
                          itinerary: buildTrackingItinerary(
                              networkAsync.value!, route, bus),
                          legIndex: 0,
                          busId: bus.id,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Remaining stops ahead of the bus, each with a live arrival estimate.
  List<({String name, int minutes})> _nextStops(
    TransitRoute route,
    LiveBus bus,
    DateTime now,
    ServiceClass serviceClass,
  ) {
    final out = <({String name, int minutes})>[];
    for (final ref0 in route.stops) {
      if (ref0.seq <= bus.nextStopSeq) continue;
      final remainingKm =
          (ref0.cumKm - bus.travelledKm).abs().clamp(0.0, route.distanceKm);
      final remainingStops = route.stops.length - ref0.seq;
      final eta = EtaEngine.predictArrival(
        remainingKm: remainingKm,
        currentKmph: bus.speedKmph,
        now: now,
        serviceClass: serviceClass,
        remainingStops: remainingStops,
      );
      out.add((
        name: ref0.name.isEmpty ? ref0.city : ref0.name,
        minutes: eta.minutesRemaining,
      ));
      if (out.length >= 6) break;
    }
    return out;
  }

}

/// The library's drag handle is owned by [showModalBottomSheet]; the map
/// overlays a static panel instead, so it draws its own.
class SkeletonDividerHandle extends StatelessWidget {
  const SkeletonDividerHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: palette.hairlineStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _NextStopRow extends StatelessWidget {
  final String name;
  final int minutes;
  const _NextStopRow({required this.name, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
              border: Border.all(color: palette.brand, width: 2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(
            minutes <= 0 ? 'now' : '$minutes min',
            style: theme.textTheme.labelMedium?.copyWith(
              color: minutes <= 10 ? palette.success : palette.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stop Bottom Sheet — real departures, real hand-off
// ─────────────────────────────────────────────────────────────────────────────

class _StopBottomSheet extends ConsumerWidget {
  final NetworkStop stop;
  final VoidCallback onClose;

  const _StopBottomSheet({required this.stop, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final departuresAsync = ref.watch(departuresFromStopProvider(stop.id));

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl)),
        boxShadow: AppShadow.floating(Colors.black),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: SkeletonDividerHandle()),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.brandLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_bus_filled_rounded,
                    color: palette.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stop.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${stop.city} · ${stop.depot}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded,
                        color: palette.inkMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── What actually leaves from here, soonest first ────────────
            departuresAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Row(
                  children: [
                    SkeletonBox(width: 44, height: 44,
                        borderRadius: AppSpacing.brMd),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 150, height: 13),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(width: 100, height: 11),
                      ],
                    )),
                  ],
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (departures) {
                if (departures.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md),
                    child: Text(
                      'No scheduled departures from this stop right now.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                final top = departures.take(2).toList();
                return Column(
                  children: [
                    for (final dep in top)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'to ${dep.destinationName} · ${dep.service.busType}',
                                style: theme.textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TagChip(
                              label: dep.next.minutesUntil <= 0
                                  ? 'now'
                                  : '${dep.next.minutesUntil} min',
                              dense: true,
                              foreground: dep.next.minutesUntil <= 30
                                  ? palette.success
                                  : palette.inkSoft,
                              background: dep.next.minutesUntil <= 30
                                  ? palette.successLight
                                  : palette.surfaceAlt,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Find routes from here',
              icon: Icons.search_rounded,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        JourneySearchScreen(initialOrigin: stop),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking Card — no more invented rows; recents are real or absent
// ─────────────────────────────────────────────────────────────────────────────

class _BookingCard extends ConsumerWidget {
  final VoidCallback onSearchTap;
  const _BookingCard({required this.onSearchTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final recents = ref.watch(recentSearchesProvider);
    final networkAsync = ref.watch(networkProvider);
    final network = networkAsync.value;

    // Resolve the recent routes' stop ids against the active network; a stale
    // id from a different state is skipped rather than shown broken.
    final recentRoutes = <({NetworkStop origin, NetworkStop destination})>[];
    for (final r in recents.take(3)) {
      final o = network?.stopById(r.originStopId);
      final d = network?.stopById(r.destinationStopId);
      if (o != null && d != null) {
        recentRoutes.add((origin: o, destination: d));
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: palette.hairline),
        boxShadow: AppShadow.raised(Colors.black),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan your journey',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.md),
                GestureDetector(
                  onTap: onSearchTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: 14),
                    decoration: BoxDecoration(
                      color: palette.canvas,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: palette.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded,
                            color: palette.inkMuted, size: 22),
                        const SizedBox(width: AppSpacing.lg),
                        Text(
                          'Where to?',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: palette.inkFaint),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Only show recents that actually exist. Empty history shows nothing
          // rather than invented rows.
          if (network != null && recentRoutes.isNotEmpty) ...[
            Divider(height: 1, color: palette.hairline),
            for (final route in recentRoutes)
              _RecentRouteRow(
                route: route,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JourneySearchScreen(
                      initialOrigin: route.origin,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ] else
            const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _RecentRouteRow extends StatelessWidget {
  final ({NetworkStop origin, NetworkStop destination}) route;
  final VoidCallback onTap;

  const _RecentRouteRow({required this.route, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_rounded,
                  color: palette.inkMuted, size: 18),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                '${route.origin.city} → ${route.destination.city}',
                style: Theme.of(context).textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: palette.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }
}
