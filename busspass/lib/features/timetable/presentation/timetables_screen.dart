import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

/// Full-screen bus timetable view.
///
/// Reads the bundled departure boards (one per depot origin) from the offline
/// network rather than Firestore, so it works with no signal. Each row is a
/// destination served from that depot, with its upcoming and passed departures
/// aligned to the current time.
class TimetablesScreen extends ConsumerWidget {
  const TimetablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originsAsync = ref.watch(timetableOriginsProvider);
    final now = ref.watch(clockProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Timetables',
            style: TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      body: originsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text('Could not load timetables: $e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (origins) {
          if (origins.isEmpty) {
            return const Center(
              child: Text(
                'No departure boards available',
                style: TextStyle(color: AppColors.inkMuted),
              ),
            );
          }
          return _DepotBoards(origins: origins, now: now);
        },
      ),
    );
  }
}

class _DepotBoards extends ConsumerWidget {
  final List<NetworkStop> origins;
  final DateTime now;

  const _DepotBoards({required this.origins, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the existing single-depot feel: show all boards grouped by origin,
    // each origin rendered as a section of destination cards.
    final allBoards = <({String origin, String destination, String busType,
        List<int> departures, double? distanceKm})>[];

    for (final origin in origins) {
      final rows = ref.watch(timetableRowsProvider(origin.id));
      final resolved = rows.value ?? const [];
      for (final row in resolved) {
        allBoards.add((
          origin: origin.city,
          destination: row.destination,
          busType: row.busType,
          departures: row.departures,
          distanceKm: row.distanceKm,
        ));
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xxl),
      itemCount: allBoards.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final board = allBoards[i];
        return _TimetableCard(
          origin: board.origin,
          destination: board.destination,
          busType: board.busType,
          departures: board.departures,
          distanceKm: board.distanceKm,
          now: now,
        );
      },
    );
  }
}

class _TimetableCard extends StatelessWidget {
  final String origin;
  final String destination;
  final String busType;
  final List<int> departures;
  final double? distanceKm;
  final DateTime now;

  const _TimetableCard({
    required this.origin,
    required this.destination,
    required this.busType,
    required this.departures,
    required this.distanceKm,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = Schedule.statusFor(departures, now);
    final upcoming = status.upcoming.take(8).toList();
    final passed = status.passed.take(8).toList();

    final canSearch = origin.isNotEmpty && destination.isNotEmpty;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brandLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.location_city_rounded,
                    color: AppColors.brand, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_titleCase(destination),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      [if (busType.isNotEmpty) busType,
                        if (distanceKm != null) '${distanceKm!.round()} km',
                        if (canSearch) origin,]
                            .join(' · '),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (upcoming.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${upcoming.length} next',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (upcoming.isNotEmpty) ...[
            Text('Upcoming',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.brand)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: upcoming.map((d) {
                final diff = d.minutesUntil;
                final rel = Schedule.formatDuration(diff);
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: diff <= 30
                            ? AppColors.brand
                            : AppColors.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Schedule.formatClock(d.minuteOfDay),
                          style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: diff <= 30
                                  ? AppColors.brand
                                  : AppColors.ink)),
                      if (diff <= 30) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(rel,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.brand, fontSize: 9)),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          if (passed.isNotEmpty) ...[
            Text('Earlier today',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: passed.map((d) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Text(Schedule.formatClock(d.minuteOfDay),
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.inkMuted,
                            decoration: TextDecoration.lineThrough)),
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
}
