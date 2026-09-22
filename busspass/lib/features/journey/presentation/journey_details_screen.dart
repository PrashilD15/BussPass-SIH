import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/geo.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/providers/directions_provider.dart';
import 'package:busspass/features/journey/presentation/live_navigation_screen.dart';
import 'package:busspass/core/utils/bus_image_helper.dart';
import 'package:busspass/core/ui/responsive_wrapper.dart';
import 'package:busspass/core/theme/map_style.dart';
import 'package:busspass/core/utils/map_marker_utils.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
import 'package:busspass/features/journey/presentation/walk_to_stand_screen.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:busspass/theme/widgets/brand_mark.dart';

/// Journey results for an origin/destination pair, backed by the offline
/// transit network and the graph planner.
class JourneyDetailsScreen extends ConsumerStatefulWidget {
  final String originId;
  final String destinationId;
  final DateTime? departAfter;
  final int adultCount;
  final int ladyCount;
  final int childCount;

  const JourneyDetailsScreen({
    super.key,
    required this.originId,
    required this.destinationId,
    this.departAfter,
    this.adultCount = 1,
    this.ladyCount = 0,
    this.childCount = 0,
  });

  @override
  ConsumerState<JourneyDetailsScreen> createState() =>
      _JourneyDetailsScreenState();
}

class _JourneyDetailsScreenState extends ConsumerState<JourneyDetailsScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final originAsync = ref.watch(stopProvider(widget.originId));
    final destAsync = ref.watch(stopProvider(widget.destinationId));
    final now = ref.watch(clockProvider);
    final preference = ref.watch(journeyPreferenceProvider);

    return ResponsiveWrapper(
      child: originAsync.when(
        loading: () => const _LoadingScaffold(),
        error: (e, _) => _ErrorScaffold(message: '$e'),
        data: (origin) {
          return destAsync.when(
            loading: () => const _LoadingScaffold(),
            error: (e, _) => _ErrorScaffold(message: '$e'),
            data: (destination) {
              if (origin == null || destination == null) {
                return _ErrorScaffold(message: 'Stop not found');
              }
              return _buildContent(origin, destination, now, preference);
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(NetworkStop origin, NetworkStop destination,
      DateTime now, JourneyPreference preference) {
    final query = JourneyQuery(
      originId: origin.id,
      destinationId: destination.id,
      departAfter: widget.departAfter ?? now,
      preference: preference,
      adultCount: widget.adultCount,
      ladyCount: widget.ladyCount,
      childCount: widget.childCount,
    );
    final plansAsync = ref.watch(journeyPlanProvider(query));
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: plansAsync.when(
        loading: () => const Center(child: BrandLoader()),
        error: (err, stack) => ErrorState(
          message: 'We could not plan this journey right now. '
              'Please try again in a moment.',
          detail: err,
          onRetry: () => ref.invalidate(journeyPlanProvider(query)),
        ),
        data: (itineraries) {
          if (itineraries.isEmpty) {
            return _NoRouteFound(
              originCity: origin.city,
              destCity: destination.city,
            );
          }

          final primary = itineraries[_selectedIndex
              .clamp(0, itineraries.length - 1)];

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 260,
                    pinned: true,
                    backgroundColor: palette.brand,
                    leading: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: palette.ink, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: _RouteMap(
                        origin: origin,
                        destination: destination,
                        itinerary: primary,
                      ),
                      title: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.palette.scrim(0.54),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${origin.city} → ${destination.city}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      centerTitle: true,
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                      child: _OverviewCard(
                        itinerary: primary,
                        adultCount: widget.adultCount,
                        ladyCount: widget.ladyCount,
                      ),
                    ),
                  ),

                  // ── Ranking preference — re-plans live through the planner ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                      child: _PreferenceSelector(
                        current: preference,
                        onChanged: (p) => ref
                            .read(settingsProvider.notifier)
                            .setJourneyPreference(p),
                      ),
                    ),
                  ),

                  if (primary.transferCount > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.xl, AppSpacing.lg, 0),
                        child: _TransferBanner(itinerary: primary),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.xl, AppSpacing.lg, 0),
                      child: _ItineraryOptions(
                        itineraries: itineraries,
                        selectedIndex: _selectedIndex,
                        onSelect: (i) =>
                            setState(() => _selectedIndex = i),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.xl, AppSpacing.lg, 0),
                      child: _BoardingGuideCard(
                        itinerary: primary,
                        origin: origin,
                        destination: destination,
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.xl, AppSpacing.lg, 0),
                      child: _LegsCard(
                        itinerary: primary,
                        adultCount: widget.adultCount,
                        ladyCount: widget.ladyCount,
                        childCount: widget.childCount,
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),

              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: PrimaryButton(
                  label: primary.isDirect
                      ? 'Start Journey'
                      : 'Start Journey · ${primary.transferCount} transfer',
                  icon: Icons.directions_bus_rounded,
                  onPressed: () => _onStartJourney(primary),
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

  void _showBoardingDialog(Itinerary itinerary) {
    final palette = context.palette;
    showModalBottomSheet(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
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
                color: palette.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.brandLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_bus_rounded,
                size: 28,
                color: palette.brand,
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
              'We will start syncing your GPS to track the\njourney on ${itinerary.origin.city} → ${itinerary.destination.city}.',
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
                // Issuing a ticket here is what makes the Passes tab real:
                // the entitlement exists, is persisted, and its boarding
                // reminder is scheduled by TicketsNotifier.
                final settings = ref.read(settingsProvider);
                final totalPassengers =
                    widget.adultCount + widget.ladyCount + widget.childCount;
                final category = settings.riderCategory != RiderCategory.adult
                    ? settings.riderCategory
                    : (widget.ladyCount > widget.adultCount + widget.childCount
                        ? RiderCategory.woman
                        : RiderCategory.adult);
                ref.read(ticketsProvider.notifier).add(
                      Ticket.fromItinerary(
                        itinerary,
                        riderCategory: category,
                        passengers: totalPassengers.clamp(1, 6),
                      ),
                    );
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveNavigationScreen(
                        itinerary: itinerary, legIndex: 0),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  /// Called when "Start Journey" is tapped.
  /// Checks if user is within 100m of the first boarding stop.
  /// If not → opens WalkToStandScreen first.
  Future<void> _onStartJourney(Itinerary itinerary) async {
    if (itinerary.legs.isEmpty) {
      _showBoardingDialog(itinerary);
      return;
    }

    final firstStop = itinerary.legs.first.boardStop;

    try {
      geo.LocationPermission perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        if (mounted) _showBoardingDialog(itinerary);
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final dist = Geo.distanceMeters(
        GeoPoint(pos.latitude, pos.longitude),
        GeoPoint(firstStop.lat, firstStop.lng),
      );

      if (!mounted) return;

      if (dist > 100) {
        // User is not at the stand — redirect to walk-to-stand
        final arrived = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => WalkToStandScreen(
              targetStand: NetworkStop(
                id: firstStop.id,
                name: firstStop.name,
                city: firstStop.city,
                depot: '',
                district: '',
                lat: firstStop.lat,
                lng: firstStop.lng,
              ),
            ),
          ),
        );
        if (!mounted) return;
        if (arrived == true) _showBoardingDialog(itinerary);
      } else {
        _showBoardingDialog(itinerary);
      }
    } catch (_) {
      if (mounted) _showBoardingDialog(itinerary);
    }
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: const Center(child: BrandLoader()),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: ErrorState(
        message: 'We could not load this journey. '
            'Please try again in a moment.',
        detail: message,
      ),
    );
  }
}

// ── Overview stats ──────────────────────────────────────────────────────────
class _OverviewCard extends ConsumerWidget {
  final Itinerary itinerary;
  final int adultCount;
  final int ladyCount;

  const _OverviewCard({
    required this.itinerary,
    required this.adultCount,
    required this.ladyCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    
    double activeDistanceKm = itinerary.distanceKm;
    int activeDurationMins = itinerary.totalMinutes;

    for (final leg in itinerary.legs) {
      final via = leg.intermediateStops
          .map((s) => LatLng(s.lat, s.lng))
          .toList(growable: false);
      final legRef = TransLegRef(
        origin: LatLng(leg.boardStop.lat, leg.boardStop.lng),
        via: via,
        destination: LatLng(leg.alightStop.lat, leg.alightStop.lng),
      );

      final result = ref.watch(legDirectionsViewProvider(legRef));
      if (result != null) {
        activeDistanceKm = activeDistanceKm - leg.distanceKm + (result.distanceMeters / 1000.0);
        activeDurationMins = activeDurationMins - leg.estimate.totalMinutes + (result.durationSeconds ~/ 60);
      }
    }

    return AppCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Fare ${adultCount > 0 && ladyCount > 0 ? "(${adultCount}A, ${ladyCount}L)" : ladyCount > 0 ? "(${ladyCount}L)" : adultCount > 1 ? "(${adultCount}A)" : ""}',
            value: FareEngine.formatRupees(itinerary.totalFare),
            icon: Icons.account_balance_wallet_outlined,
          ),
          Container(width: 1, height: 40, color: palette.hairline),
          _StatItem(
            label: 'Est. Time',
            value: Schedule.formatDuration(activeDurationMins),
            icon: Icons.timer_outlined,
          ),
          Container(width: 1, height: 40, color: palette.hairline),
          _StatItem(
            label: 'Distance',
            value: '${activeDistanceKm.round()} km',
            icon: Icons.map_outlined,
          ),
        ],
      ),
    ).animate().slideY(
        begin: 0.15, duration: 500.ms, curve: Curves.easeOutCubic);
  }
}

// ── Ranking preference selector ────────────────────────────────────────────
//
// Changing this re-keys the planner query (journeyPlanProvider is family over
// JourneyQuery, which carries the preference), so the ranked results below
// rebuild genuinely — not just re-sorted client-side.
class _PreferenceSelector extends StatelessWidget {
  final JourneyPreference current;
  final ValueChanged<JourneyPreference> onChanged;

  const _PreferenceSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('details.rank_by'.tr(), style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final pref in JourneyPreference.values)
              ChoiceChip(
                selected: pref == current,
                onSelected: (_) => onChanged(pref),
                label: Text(_label(pref)),
              ),
          ],
        ),
      ],
    );
  }

  static String _label(JourneyPreference p) => switch (p) {
        JourneyPreference.fastest => 'details.pref_fastest'.tr(),
        JourneyPreference.cheapest => 'details.pref_cheapest'.tr(),
        JourneyPreference.fewestChanges => 'details.pref_fewest'.tr(),
        JourneyPreference.earliestArrival => 'details.pref_earliest'.tr(),
      };
}

class _TransferBanner extends StatelessWidget {
  final Itinerary itinerary;
  const _TransferBanner({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final transfer = itinerary.transfers.firstOrNull;
    final city = transfer?.stop.city ?? 'a transfer stop';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.warningLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: palette.warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded,
              color: palette.warning, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connecting Journey — ${itinerary.transferCount} Transfer',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13, color: palette.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  'Change buses at $city. '
                  '${itinerary.hasSleeper ? 'Overnight service.' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12, color: palette.warning),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Itinerary option cards ──────────────────────────────────────────────────
class _ItineraryOptions extends StatelessWidget {
  final List<Itinerary> itineraries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _ItineraryOptions({
    required this.itineraries,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (itineraries.length == 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Route Options',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontSize: 19),
        ),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(itineraries.length, (i) {
          final it = itineraries[i];
          final isSelected = i == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ItineraryCard(
              itinerary: it,
              isSelected: isSelected,
              onTap: () => onSelect(i),
            ),
          );
        }),
      ],
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final bool isSelected;
  final VoidCallback onTap;

  const _ItineraryCard({
    required this.itinerary,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final serviceClass = itinerary.legs.first.serviceClass;
    final busType = serviceClass.label;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isSelected ? palette.brandLight : palette.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? palette.brand : palette.hairline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Builder(builder: (context) {
              final imageUrl = BusImageHelper.getImageUrl(busType);
              return Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? palette.brand : palette.canvas,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  image: imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                          colorFilter: isSelected
                              ? ColorFilter.mode(
                                  palette.brand.withValues(alpha: 0.55),
                                  BlendMode.srcATop)
                              : null,
                        )
                      : null,
                ),
                child: imageUrl == null || isSelected
                    ? Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.directions_bus_outlined,
                        color: isSelected ? palette.onBrand : palette.inkMuted,
                        size: 24,
                      )
                    : null,
              );
            }),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itinerary.isDirect
                        ? 'Direct · ${serviceClass.label}'
                        : '${itinerary.transferCount} transfers · ${serviceClass.label}',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.departure_board_rounded, size: 14, color: palette.brand),
                      const SizedBox(width: 4),
                      Text(
                        Schedule.formatClock(Schedule.minuteOfDay(itinerary.departsAt)),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_rounded, size: 14, color: palette.brand),
                      const SizedBox(width: 4),
                      Text(
                        Schedule.formatClock(Schedule.minuteOfDay(itinerary.arrivesAt)),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              FareEngine.formatRupees(itinerary.totalFare),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    color: palette.brand,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Boarding guide ──────────────────────────────────────────────────────────
class _BoardingGuideCard extends StatelessWidget {
  final Itinerary itinerary;
  final NetworkStop origin;
  final NetworkStop destination;

  const _BoardingGuideCard({
    required this.itinerary,
    required this.origin,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final firstLeg = itinerary.legs.first;
    final serviceClass = firstLeg.serviceClass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How to Board',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 19)),
        const SizedBox(height: AppSpacing.md),
        _StepCard(
          stepNumber: '1',
          stepColor: palette.brand,
          icon: Icons.place_rounded,
          title: 'Go to ${firstLeg.boardStop.name}',
          subtitle: Text(
              '${firstLeg.boardStop.city}'
              '${firstLeg.boardStop.depot.isNotEmpty ? ' · ${firstLeg.boardStop.depot}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          trailing: null,
        ),
        const SizedBox(height: AppSpacing.sm),
        _StepCard(
          stepNumber: '2',
          stepColor: palette.success,
          icon: Icons.directions_bus_rounded,
          title: 'Board: ${serviceClass.label}',
          subtitle: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, height: 1.3),
              children: [
                TextSpan(text: 'Tell conductor: "${firstLeg.alightStop.city}"\n'),
                TextSpan(
                  text: 'DEPARTS ${Schedule.formatClock(Schedule.minuteOfDay(firstLeg.departsAt))}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: palette.success),
                ),
              ],
            ),
          ),
          trailing: _BusBoardingImage(busType: serviceClass.key),
        ),
        const SizedBox(height: AppSpacing.sm),
        _NextDepartureCard(itinerary: itinerary),

        if (itinerary.transfers.isNotEmpty)
          for (final (index, gap) in itinerary.transfers.indexed) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.inkSoft.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                    color: palette.inkSoft.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded,
                          size: 18, color: palette.inkSoft),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Transfer ${index + 1} at ${gap.stop.name} '
                          '· wait ${gap.waitMinutes} min',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontSize: 13, color: palette.inkSoft),
                        ),
                      ),
                    ],
                  ),
                  if (gap.walkKm > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Walk ${gap.walkKm.toStringAsFixed(1)} km between stands.',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _StepCard(
                    stepNumber: '${index + 3}',
                    stepColor: palette.accent,
                    icon: Icons.directions_bus_filled_rounded,
                    title:
                        'Board: ${itinerary.legs[index + 1].serviceClass.label}',
                    subtitle: Text(
                        '${gap.stop.city} → ${itinerary.legs[index + 1].alightStop.city}'
                        ' · ${FareEngine.formatRupees(itinerary.legs[index + 1].fare)}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    trailing: _BusBoardingImage(
                        busType: itinerary.legs[index + 1].serviceClass.key),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final String stepNumber;
  final Color stepColor;
  final IconData icon;
  final String title;
  final Widget subtitle;
  final Widget? trailing;

  const _StepCard({
    required this.stepNumber,
    required this.stepColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            color: stepColor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                Text(
                  stepNumber,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 14,
                        color: stepColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Icon(icon, size: 18, color: stepColor),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  subtitle,
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _BusBoardingImage extends StatelessWidget {
  final String busType;
  const _BusBoardingImage({required this.busType});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = BusImageHelper.getImageUrl(busType);
    if (url == null) {
      return Container(
        width: 72,
        height: 60,
        color: palette.canvas,
        child: Icon(Icons.directions_bus_outlined,
            color: palette.inkMuted, size: 28),
      );
    }
    return Container(
      width: 80,
      height: 64,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(url),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _NextDepartureCard extends ConsumerWidget {
  final Itinerary itinerary;
  const _NextDepartureCard({required this.itinerary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final firstLeg = itinerary.legs.first;
    final departsAt = firstLeg.departsAt;

    final via = firstLeg.intermediateStops
        .map((s) => LatLng(s.lat, s.lng))
        .toList(growable: false);
    final legRef = TransLegRef(
      origin: LatLng(firstLeg.boardStop.lat, firstLeg.boardStop.lng),
      via: via,
      destination: LatLng(firstLeg.alightStop.lat, firstLeg.alightStop.lng),
    );
    final result = ref.watch(legDirectionsViewProvider(legRef));
    final displayDistanceKm = result != null ? (result.distanceMeters / 1000.0) : firstLeg.distanceKm;
    final displayDurationMins = result != null ? (result.durationSeconds ~/ 60) : firstLeg.estimate.totalMinutes;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: palette.brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: palette.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: palette.brand,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DEPARTS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: palette.onBrand,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      Schedule.formatClock(Schedule.minuteOfDay(departsAt)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.brand,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '·  ${Schedule.formatDuration(displayDurationMins)} onboard',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.brand.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${displayDistanceKm.round()} km · '
                  'via ${firstLeg.route.distanceKm.round()} km corridor',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legs / fares breakdown ───────────────────────────────────────────────────
/// Adult-fare total before any concession, for the receipt-style breakdown.
int adultBaseSum(Itinerary itinerary) => itinerary.legs.fold(0, (sum, leg) {
      final serviceClass = leg.serviceClass;
      final base = FareEngine.compute(
        distanceKm: leg.distanceKm,
        serviceClass: serviceClass,
      );
      return sum + base.baseFare;
    });

/// The rider's concession, surfaced with a live example: this trip, this
/// category, this many rupees off. Comes from [settingsProvider] so it's the
/// category they actually picked in Profile, not a guess.
class _ConcessionRow extends ConsumerWidget {
  final int adultTotal;
  const _ConcessionRow({required this.adultTotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(settingsProvider.select((s) => s.riderCategory));
    if (category.discountPercent == 0) return const SizedBox.shrink();
    final saved = (adultTotal * category.discountPercent / 100).round();
    final theme = Theme.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'details.concession_row'.tr(namedArgs: {
                'category': category.label,
                'pct': '${category.discountPercent}',
              }),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text('- ${FareEngine.formatRupees(saved)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.success,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _LegsCard extends StatelessWidget {
  final Itinerary itinerary;
  final int adultCount;
  final int ladyCount;
  final int childCount;

  const _LegsCard({
    required this.itinerary,
    required this.adultCount,
    required this.ladyCount,
    required this.childCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Journey & Fare',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 17)),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < itinerary.legs.length; i++) ...[
            _LegRow(leg: itinerary.legs[i], index: i),
            if (i < itinerary.legs.length - 1)
              Divider(height: 28, color: palette.hairline),
          ],
          Divider(height: 28, color: palette.hairline),
          
          if (adultCount > 0 || ladyCount > 0 || childCount > 0) ...[
            Builder(builder: (context) {
              int adultTotal = 0;
              int ladyTotal = 0;
              int childTotal = 0;
              for (var leg in itinerary.legs) {
                adultTotal += FareEngine.calculateTotalTripFare(leg.distanceKm, leg.service.serviceClass.key, adultCount, 0, 0, operatorName: leg.route.operatorName);
                ladyTotal += FareEngine.calculateTotalTripFare(leg.distanceKm, leg.service.serviceClass.key, 0, ladyCount, 0, operatorName: leg.route.operatorName);
                childTotal += FareEngine.calculateTotalTripFare(leg.distanceKm, leg.service.serviceClass.key, 0, 0, childCount, operatorName: leg.route.operatorName);
              }
              return Column(
                children: [
                  if (adultCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Adults ($adultCount)', style: theme.textTheme.bodyMedium),
                          Text(FareEngine.formatRupees(adultTotal), style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  if (ladyCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Ladies ($ladyCount)', style: theme.textTheme.bodyMedium),
                          Text(FareEngine.formatRupees(ladyTotal), style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  if (childCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Children ($childCount)', style: theme.textTheme.bodyMedium),
                          Text(FareEngine.formatRupees(childTotal), style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                ],
              );
            }),
            Divider(height: 16, color: palette.hairline),
          ],

          _ConcessionRow(adultTotal: adultBaseSum(itinerary)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Passenger Fare',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                FareEngine.formatRupees(itinerary.totalFare),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 17, color: palette.brand),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegRow extends ConsumerWidget {
  final JourneyLeg leg;
  final int index;
  const _LegRow({required this.leg, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    
    final via = leg.intermediateStops
        .map((s) => LatLng(s.lat, s.lng))
        .toList(growable: false);
    final legRef = TransLegRef(
      origin: LatLng(leg.boardStop.lat, leg.boardStop.lng),
      via: via,
      destination: LatLng(leg.alightStop.lat, leg.alightStop.lng),
    );
    final result = ref.watch(legDirectionsViewProvider(legRef));
    final displayDistanceKm = result != null ? (result.distanceMeters / 1000.0) : leg.distanceKm;
    
    // Extract stop names for intermediate stops
    final viaStops = leg.intermediateStops.map((s) => s.name).toList();
    final viaText = viaStops.isEmpty ? '' : 'via ${viaStops.join(', ')}';

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: palette.brandLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(leg.serviceClass.ac
              ? Icons.ac_unit_rounded
              : Icons.directions_bus_outlined,
              color: palette.brand, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${leg.boardStop.city} → ${leg.alightStop.city}',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              // Published depot board vs synthesised headway — the rider
              // deserves to know which clock to trust.
              ScheduleConfidenceBadge(confidence: leg.service.confidence),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    Schedule.formatClock(Schedule.minuteOfDay(leg.departsAt)),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                  Icon(Icons.arrow_right_alt_rounded, size: 14, color: palette.inkMuted),
                  Text(
                    Schedule.formatClock(Schedule.minuteOfDay(leg.arrivesAt)),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '·  ${leg.serviceClass.label} · ${displayDistanceKm.round()} km',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, color: palette.inkMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (viaText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  viaText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 11, 
                    color: palette.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        Text(
          FareEngine.formatRupees(leg.fare),
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 16, color: palette.brand),
        ),
      ],
    );
  }
}

// ── Map ──────────────────────────────────────────────────────────────────────
class _RouteMap extends ConsumerStatefulWidget {
  final NetworkStop origin;
  final NetworkStop destination;
  final Itinerary itinerary;

  const _RouteMap({
    required this.origin,
    required this.destination,
    required this.itinerary,
  });

  @override
  ConsumerState<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends ConsumerState<_RouteMap> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  late AnimationController _animController;
  late Animation<double> _animation;
  BitmapDescriptor? _originMarker;
  BitmapDescriptor? _destMarker;
  BitmapDescriptor? _viaMarker;
  final Map<String, BitmapDescriptor> _viaMarkersMap = {};
  
  List<LatLng> _cachedPoints = [];
  LatLng? _cachedCenter;
  final Map<String, int> _markerIndexCache = {};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _animation = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.addListener(() {
      if (mounted) setState(() {});
    });

    _loadMarkers();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadMarkers() async {
    final palette = context.palette;
    _originMarker = widget.origin.imageUrl != null
        ? await MapMarkerUtils.createImageMarker(
            imageUrl: widget.origin.imageUrl!, color: palette.info, size: 48)
        : await MapMarkerUtils.createCustomMarker(
            color: palette.info, size: 48);
    _destMarker = widget.destination.imageUrl != null
        ? await MapMarkerUtils.createImageMarker(
            imageUrl: widget.destination.imageUrl!, color: palette.success, size: 56)
        : await MapMarkerUtils.createCustomMarker(
            color: palette.success, size: 56, isDestination: true);
    _viaMarker = await MapMarkerUtils.createCustomMarker(
        color: palette.accent, size: 36);

    final network = ref.read(networkProvider);
    for (final leg in widget.itinerary.legs) {
      for (final s in leg.intermediateStops) {
        final netStop = network.value?.stopById(s.stopId);
        if (netStop != null && netStop.imageUrl != null) {
          _viaMarkersMap['${leg.route.id}-${s.stopId}'] = await MapMarkerUtils.createImageMarker(
              imageUrl: netStop.imageUrl!, color: palette.accent, size: 36);
        }
      }
    }

    if (mounted) setState(() {});
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitBounds();
  }

  void _fitBounds() {
    if (_mapController == null) return;
    _updateCache();
    final points = _cachedPoints;
    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLat = points.first.latitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Delay slightly to ensure layout is done
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            60.0, // padding
          ),
        ).then((_) {
          if (mounted) {
            _animController.forward();
          }
        });
      }
    });
  }

  void _updateCache() {
    final points = <LatLng>[];
    if (widget.itinerary.legs.isEmpty) {
      points.add(LatLng(widget.origin.lat, widget.origin.lng));
      points.add(LatLng(widget.destination.lat, widget.destination.lng));
    } else {
      for (final leg in widget.itinerary.legs) {
        final via = leg.intermediateStops
            .map((s) => LatLng(s.lat, s.lng))
            .toList(growable: false);
        final legRef = TransLegRef(
          origin: LatLng(leg.boardStop.lat, leg.boardStop.lng),
          via: via,
          destination: LatLng(leg.alightStop.lat, leg.alightStop.lng),
        );

        final road = ref.watch(legRoadPolylineViewProvider(legRef));
        if (road != null && road.isNotEmpty) {
          points.addAll(road);
        } else {
          points.addAll(legRef.points);
        }
      }
    }
    
    if (points.isNotEmpty && _cachedPoints.length != points.length) {
      _cachedPoints = points;
      
      final latSum = points.fold<double>(0, (a, p) => a + p.latitude);
      final lngSum = points.fold<double>(0, (a, p) => a + p.longitude);
      _cachedCenter = LatLng(latSum / points.length, lngSum / points.length);
      
      // Cache the marker indices so we don't scan the array every frame
      for (final leg in widget.itinerary.legs) {
        for (final s in leg.intermediateStops) {
          final key = '${leg.route.id}-${s.stopId}';
          final idx = points.indexWhere((p) => p.latitude == s.lat && p.longitude == s.lng);
          if (idx != -1) _markerIndexCache[key] = idx;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateCache();
    
    final palette = context.palette;
    final allPoints = _cachedPoints;
    
    if (allPoints.isEmpty) {
      return Container(color: palette.canvas);
    }
    
    final int pointsToShow = (allPoints.length * _animation.value).ceil();
    final points = allPoints.take(pointsToShow).toList();

    final center = _cachedCenter ?? LatLng(widget.origin.lat, widget.origin.lng);

    final viaMarkers = widget.itinerary.legs.expand((leg) {
      return leg.intermediateStops.map((s) {
        final key = '${leg.route.id}-${s.stopId}';
        
        // Hide markers that are ahead of the current animation
        final markerIndex = _markerIndexCache[key];
        if (markerIndex != null && markerIndex > pointsToShow) {
          return null;
        }

        return Marker(
          markerId: MarkerId('via-$key'),
          position: LatLng(s.lat, s.lng),
          icon: _viaMarkersMap[key] ?? _viaMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
              title: s.name,
              snippet: '${s.city} · ${s.cumKm.toStringAsFixed(0)} km'),
        );
      }).whereType<Marker>();
    }).toSet();

    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: points.length > 2 ? 6.2 : 7.5,
        tilt: 50.0, // 3D perspective
      ),
      style: mapStyleFor(Theme.of(context).brightness),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      polylines: {
        Polyline(
          polylineId: const PolylineId('route-sheen'),
          points: points,
          color: Colors.white.withValues(alpha: 0.65),
          width: 8,
          jointType: JointType.round,
        ),
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: palette.brand,
          width: 4,
          jointType: JointType.round,
        ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(widget.origin.lat, widget.origin.lng),
          icon: _originMarker ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(title: widget.origin.name, snippet: widget.origin.city),
        ),
        Marker(
          markerId: const MarkerId('dest'),
          position: LatLng(widget.destination.lat, widget.destination.lng),
          icon: _destMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(title: widget.destination.name, snippet: widget.destination.city),
        ),
        ...viaMarkers,
      },
    );
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
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: palette.brand, size: 22),
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
    return EmptyState(
      icon: Icons.bus_alert_rounded,
      title: 'No route found',
      message: 'No buses can get you from $originCity to $destCity '
          'within the search limits. Try a different time or destination.',
      actionLabel: 'Go Back',
      onAction: () => Navigator.pop(context),
    );
  }
}
