import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/features/journey/presentation/live_navigation_screen.dart';
import 'package:busspass/core/utils/bus_image_helper.dart';
import 'package:busspass/core/theme/map_style.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

/// Journey results for an origin/destination pair, backed by the offline
/// transit network and the graph planner.
class JourneyDetailsScreen extends ConsumerStatefulWidget {
  final String originId;
  final String destinationId;

  const JourneyDetailsScreen({
    super.key,
    required this.originId,
    required this.destinationId,
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

    return originAsync.when(
      loading: () => const _LoadingScaffold(),
      error: (e, _) => _ErrorScaffold(message: '$e'),
      data: (origin) => destAsync.when(
        loading: () => const _LoadingScaffold(),
        error: (e, _) => _ErrorScaffold(message: '$e'),
        data: (destination) {
          if (origin == null || destination == null) {
            return _ErrorScaffold(message: 'Stop not found');
          }
          return _buildContent(origin, destination, now, preference);
        },
      ),
    );
  }

  Widget _buildContent(NetworkStop origin, NetworkStop destination,
      DateTime now, JourneyPreference preference) {
    final query = JourneyQuery(
      originId: origin.id,
      destinationId: destination.id,
      departAfter: now,
      preference: preference,
    );
    final plansAsync = ref.watch(journeyPlanProvider(query));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: plansAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand),
        ),
        error: (err, stack) => Center(child: Text('Error: $err')),
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
                        origin: origin,
                        destination: destination,
                        itinerary: primary,
                      ),
                      title: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
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
                      child: _OverviewCard(itinerary: primary),
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
                      child: _LegsCard(itinerary: primary),
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
                  onPressed: () => _showBoardingDialog(primary),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
}

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(child: Text(message)),
      );
}

// ── Overview stats ──────────────────────────────────────────────────────────
class _OverviewCard extends StatelessWidget {
  final Itinerary itinerary;
  const _OverviewCard({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Total Fare',
            value: FareEngine.formatRupees(itinerary.totalFare),
            icon: Icons.account_balance_wallet_outlined,
          ),
          Container(width: 1, height: 40, color: AppColors.hairline),
          _StatItem(
            label: 'Est. Time',
            value: Schedule.formatDuration(itinerary.totalMinutes),
            icon: Icons.timer_outlined,
          ),
          Container(width: 1, height: 40, color: AppColors.hairline),
          _StatItem(
            label: 'Distance',
            value: '${itinerary.distanceKm.round()} km',
            icon: Icons.map_outlined,
          ),
        ],
      ),
    ).animate().slideY(
        begin: 0.15, duration: 500.ms, curve: Curves.easeOutCubic);
  }
}

class _TransferBanner extends StatelessWidget {
  final Itinerary itinerary;
  const _TransferBanner({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    final transfer = itinerary.transfers.firstOrNull;
    final city = transfer?.stop.city ?? 'a transfer stop';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded,
              color: Color(0xFF7B5800), size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connecting Journey — ${itinerary.transferCount} Transfer',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13, color: const Color(0xFF7B5800)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Change buses at $city. '
                  '${itinerary.hasSleeper ? 'Overnight service.' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12, color: const Color(0xFF7B5800)),
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
    final serviceClass = itinerary.legs.first.serviceClass;
    final busType = serviceClass.label;
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
            Builder(builder: (context) {
              final imageUrl = BusImageHelper.getImageUrl(busType);
              return Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.brand : AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  image: imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                          colorFilter: isSelected
                              ? ColorFilter.mode(
                                  AppColors.brand.withValues(alpha: 0.55),
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
                        color: isSelected ? Colors.white : AppColors.inkMuted,
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
                  Text(
                    'Departs ${Schedule.formatClock(Schedule.minuteOfDay(itinerary.departsAt))} · '
                    'arrives ${Schedule.formatClock(Schedule.minuteOfDay(itinerary.arrivesAt))}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              FareEngine.formatRupees(itinerary.totalFare),
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
          stepColor: AppColors.brand,
          icon: Icons.place_rounded,
          title: 'Go to ${firstLeg.boardStop.name}',
          subtitle: '${firstLeg.boardStop.city}'
              '${firstLeg.boardStop.depot.isNotEmpty ? ' · ${firstLeg.boardStop.depot}' : ''}',
          trailing: null,
        ),
        const SizedBox(height: AppSpacing.sm),
        _StepCard(
          stepNumber: '2',
          stepColor: const Color(0xFF1B7C56),
          icon: Icons.directions_bus_rounded,
          title: 'Board: ${serviceClass.label}',
          subtitle:
              'Tell conductor: "${firstLeg.alightStop.city}" · '
              'departs ${Schedule.formatClock(Schedule.minuteOfDay(firstLeg.departsAt))}',
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
                color: const Color(0xFF2F3E46).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                    color: const Color(0xFF2F3E46).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz_rounded,
                          size: 18, color: Color(0xFF2F3E46)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Transfer ${index + 1} at ${gap.stop.name} '
                          '· wait ${gap.waitMinutes} min',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontSize: 13, color: const Color(0xFF2F3E46)),
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
                    stepColor: AppColors.accent,
                    icon: Icons.directions_bus_filled_rounded,
                    title:
                        'Board: ${itinerary.legs[index + 1].serviceClass.label}',
                    subtitle:
                        '${gap.stop.city} → ${itinerary.legs[index + 1].alightStop.city}'
                        ' · ${FareEngine.formatRupees(itinerary.legs[index + 1].fare)}',
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
  final String subtitle;
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.hairline),
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
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 11, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
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
    final url = BusImageHelper.getImageUrl(busType);
    if (url == null) {
      return Container(
        width: 72,
        height: 60,
        color: AppColors.canvas,
        child: const Icon(Icons.directions_bus_outlined,
            color: AppColors.inkMuted, size: 28),
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

class _NextDepartureCard extends StatelessWidget {
  final Itinerary itinerary;
  const _NextDepartureCard({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstLeg = itinerary.legs.first;
    final departsAt = firstLeg.departsAt;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Departs ${Schedule.formatClock(Schedule.minuteOfDay(departsAt))} · '
                  '${Schedule.formatDuration(firstLeg.estimate.totalMinutes)} onboard',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${firstLeg.distanceKm.round()} km · '
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
class _LegsCard extends StatelessWidget {
  final Itinerary itinerary;
  const _LegsCard({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              const Divider(height: 28, color: AppColors.hairline),
          ],
          const Divider(height: 28, color: AppColors.hairline),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total (adult)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                FareEngine.formatRupees(itinerary.totalFare),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 17, color: AppColors.brand),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  final JourneyLeg leg;
  final int index;
  const _LegRow({required this.leg, required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.brandLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(leg.serviceClass.ac
              ? Icons.ac_unit_rounded
              : Icons.directions_bus_outlined,
              color: AppColors.brand, size: 18),
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
              Text(
                '${leg.serviceClass.label} · '
                '${Schedule.formatClock(Schedule.minuteOfDay(leg.departsAt))} → '
                '${Schedule.formatClock(Schedule.minuteOfDay(leg.arrivesAt))} · '
                '${leg.distanceKm.round()} km',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          FareEngine.formatRupees(leg.fare),
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 16, color: AppColors.brand),
        ),
      ],
    );
  }
}

// ── Map ──────────────────────────────────────────────────────────────────────
class _RouteMap extends StatelessWidget {
  final NetworkStop origin;
  final NetworkStop destination;
  final Itinerary itinerary;

  const _RouteMap({
    required this.origin,
    required this.destination,
    required this.itinerary,
  });

  @override
  Widget build(BuildContext context) {
    final polyline = itinerary.polyline.map((p) => LatLng(p.lat, p.lng)).toList();
    final points = polyline.isNotEmpty
        ? polyline
        : <LatLng>[
            LatLng(origin.lat, origin.lng),
            LatLng(destination.lat, destination.lng),
          ];

    final latSum = points.fold<double>(0, (a, p) => a + p.latitude);
    final lngSum = points.fold<double>(0, (a, p) => a + p.longitude);
    final center = LatLng(latSum / points.length, lngSum / points.length);

    final viaMarkers = itinerary.legs.expand((leg) {
      return leg.intermediateStops.map((s) => Marker(
            markerId: MarkerId('via-${leg.route.id}-${s.stopId}'),
            position: LatLng(s.lat, s.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
                title: s.name,
                snippet: '${s.city} · ${s.cumKm.toStringAsFixed(0)} km'),
          ));
    }).toSet();

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: points.length > 2 ? 6.2 : 7.5,
      ),
      style: kModernMapStyleJson,
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
          color: AppColors.brand,
          width: 4,
          jointType: JointType.round,
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow:
              InfoWindow(title: destination.name, snippet: destination.city),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
              'No route found',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No buses can get you from $originCity to $destCity '
              'within the search limits.\nTry a different time or destination.',
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
