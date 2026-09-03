import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:busspass/data/providers/map_provider.dart';
import 'package:busspass/data/models/bus_models.dart';
import 'package:busspass/features/journey/presentation/journey_search_screen.dart';
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
  BusStop? _selectedStop;

  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(18.5204, 73.8567),
    zoom: 12,
  );

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    ref.read(userLocationProvider.future).then((position) {
      if (position != null && mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 13,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markersAsync = ref.watch(busStopMarkersProvider);

    return Scaffold(
      body: Stack(
        children: [
          markersAsync.when(
            data: (markers) => GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: _defaultCamera,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
              markers: markers,
              onTap: (_) => setState(() => _selectedStop = null),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: _defaultCamera,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
          ),

          // ── My Location FAB ──────────────────────────────────────
          Positioned(
            bottom: _selectedStop != null ? 220 : 120,
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
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          // ── Bus Stop Bottom Sheet ────────────────────────────────
          if (_selectedStop != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _StopBottomSheet(
                stop: _selectedStop!,
                onClose: () => setState(() => _selectedStop = null),
              ),
            ),

          // ── Bottom Booking Card ──────────────────────────────────
          if (_selectedStop == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: const _BookingCard(),
            ),
        ],
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.brand, size: 22),
      ),
    );
  }
}

class _StopBottomSheet extends StatelessWidget {
  final BusStop stop;
  final VoidCallback onClose;

  const _StopBottomSheet({required this.stop, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 12, AppSpacing.xl, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brandLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_bus_filled_rounded,
                  color: AppColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(stop.depot,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.inkMuted, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              TagChip(
                icon: Icons.location_city_outlined,
                label: stop.city,
              ),
              const SizedBox(width: AppSpacing.sm),
              TagChip(
                icon: Icons.my_location_rounded,
                label:
                    '${stop.lat.toStringAsFixed(4)}, ${stop.lng.toStringAsFixed(4)}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Find Routes from here',
            icon: Icons.search_rounded,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const JourneySearchScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.hairline),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const JourneySearchScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: AppColors.inkMuted, size: 22),
                        const SizedBox(width: AppSpacing.lg),
                        Text(
                          'Where to?',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.hairline),
          _QuickDestination(
            icon: Icons.history_rounded,
            title: 'Mumbai Central',
            subtitle: 'Recently visited',
          ),
          _QuickDestination(
            icon: Icons.star_rounded,
            title: 'Swargate Bus Stand',
            subtitle: 'Saved place',
            iconColor: AppColors.accent,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _QuickDestination extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  const _QuickDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: iconColor ?? AppColors.inkMuted, size: 18),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.inkMuted.withValues(alpha: 0.4), size: 20),
          ],
        ),
      ),
    );
  }
}