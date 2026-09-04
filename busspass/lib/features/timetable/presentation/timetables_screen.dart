import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

/// Full-screen bus timetable — departure-board style.
///
/// • GPS-first: nearest stand loads at the top automatically.
/// • Live search: filter any board by destination name.
/// • Countdown badge on each card shows the next departure.
/// • Split-flap-style time chips for an out-of-the-box feel.
class TimetablesScreen extends ConsumerStatefulWidget {
  const TimetablesScreen({super.key});

  @override
  ConsumerState<TimetablesScreen> createState() => _TimetablesScreenState();
}

class _TimetablesScreenState extends ConsumerState<TimetablesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final originsAsync = ref.watch(timetableOriginsProvider);
    final nearestAsync = ref.watch(nearestStopProvider);
    final now = ref.watch(clockProvider);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: Column(
        children: [
          _TimetableHeader(
            controller: _searchController,
            query: _query,
            onChanged: (q) => setState(() => _query = q.toLowerCase().trim()),
            palette: palette,
            theme: theme,
          ),
          Expanded(
            child: originsAsync.when(
              loading: () => const SkeletonList(count: 4),
              error: (e, _) => ErrorState(
                message: 'Could not load departure boards.',
                detail: e,
                onRetry: () => ref.invalidate(timetableOriginsProvider),
              ),
              data: (origins) {
                if (origins.isEmpty) {
                  return const EmptyState(
                    icon: Icons.schedule_rounded,
                    title: 'No departure boards',
                    message: 'No timetables published yet. Check back soon.',
                  );
                }
                final sorted = _sortByNearest(origins, nearestAsync);
                return _BoardList(
                  origins: sorted,
                  now: now,
                  query: _query,
                  nearestStopId: nearestAsync.value?.stop.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<NetworkStop> _sortByNearest(
    List<NetworkStop> origins,
    AsyncValue<({NetworkStop stop, double distanceKm})?> nearestAsync,
  ) {
    final nearestId = nearestAsync.value?.stop.id;
    if (nearestId == null) return origins;
    return [...origins]..sort((a, b) {
        if (a.id == nearestId) return -1;
        if (b.id == nearestId) return 1;
        return 0;
      });
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TimetableHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final AppPalette palette;
  final ThemeData theme;

  const _TimetableHeader({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.palette,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.brand, palette.brandDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppSpacing.radiusXl)),
        boxShadow: [
          BoxShadow(
            color: palette.brand.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.departure_board_rounded,
                      color: palette.onBrand.withValues(alpha: 0.85), size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Departure Boards',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: palette.onBrand,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Nearest stand shown first',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.onBrand.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                decoration: BoxDecoration(
                  color: palette.onBrand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                      color: palette.onBrand.withValues(alpha: 0.2)),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: TextStyle(color: palette.onBrand, fontSize: 15),
                  cursorColor: palette.onBrand,
                  decoration: InputDecoration(
                    hintText: 'Search destination…',
                    hintStyle: TextStyle(
                        color: palette.onBrand.withValues(alpha: 0.55),
                        fontSize: 15),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: palette.onBrand.withValues(alpha: 0.7)),
                    suffixIcon: query.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              controller.clear();
                              onChanged('');
                            },
                            child: Icon(Icons.close_rounded,
                                color: palette.onBrand.withValues(alpha: 0.7)),
                          )
                        : null,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BoardEntry {
  final NetworkStop origin;
  final TimetableRow row;
  final bool isNearest;
  const _BoardEntry(
      {required this.origin, required this.row, required this.isNearest});
}

class _BoardList extends ConsumerWidget {
  final List<NetworkStop> origins;
  final DateTime now;
  final String query;
  final String? nearestStopId;

  const _BoardList({
    required this.origins,
    required this.now,
    required this.query,
    required this.nearestStopId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allBoards = <_BoardEntry>[];
    for (final origin in origins) {
      final rows = ref.watch(timetableRowsProvider(origin.id));
      for (final row in rows.value ?? []) {
        if (query.isEmpty ||
            row.destination.toLowerCase().contains(query) ||
            origin.city.toLowerCase().contains(query)) {
          allBoards.add(_BoardEntry(
            origin: origin,
            row: row,
            isNearest: origin.id == nearestStopId,
          ));
        }
      }
    }

    if (query.isNotEmpty && allBoards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxxl),
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No routes found',
          message: 'No routes match "$query".',
        ),
      );
    }

    if (allBoards.isEmpty) return const SkeletonList(count: 5);

    // Group by origin stop
    final groups = <String, List<_BoardEntry>>{};
    for (final b in allBoards) {
      groups.putIfAbsent(b.origin.id, () => []).add(b);
    }
    final sections = groups.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageInset, AppSpacing.lg, AppSpacing.pageInset, 80),
      itemCount: sections.length,
      itemBuilder: (context, si) {
        final boards = sections[si].value;
        final isNearest = boards.first.isNearest;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StandHeader(stop: boards.first.origin, isNearest: isNearest)
                .animate()
                .fadeIn(delay: (si * 60).ms)
                .slideX(begin: -0.05),
            const SizedBox(height: AppSpacing.sm),
            ...boards.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _DepartureCard(entry: e.value, now: now)
                      .animate()
                      .fadeIn(delay: ((si * 60) + (e.key * 40)).ms)
                      .slideY(begin: 0.06),
                )),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StandHeader extends StatelessWidget {
  final NetworkStop stop;
  final bool isNearest;
  const _StandHeader({required this.stop, required this.isNearest});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isNearest ? palette.brand : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: isNearest ? null : Border.all(color: palette.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isNearest ? Icons.my_location_rounded : Icons.location_on_outlined,
            size: 13,
            color: isNearest ? palette.onBrand : palette.inkMuted,
          ),
          const SizedBox(width: 4),
          Text(
            isNearest ? 'Nearest — ${stop.city}' : stop.city,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isNearest ? palette.onBrand : palette.inkMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DepartureCard extends StatelessWidget {
  final _BoardEntry entry;
  final DateTime now;
  const _DepartureCard({required this.entry, required this.now});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final row = entry.row;
    final status = Schedule.statusFor(row.departures, now);
    final upcoming = status.upcoming.take(6).toList();
    final passed = status.passed.take(3).toList();
    final next = upcoming.isNotEmpty ? upcoming.first : null;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: palette.hairline),
        boxShadow: [
          BoxShadow(
            color: palette.brand.withValues(alpha: context.isDark ? 0.04 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.brandLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                  ),
                  child: Text(
                    row.busType.isEmpty ? 'Bus' : row.busType,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.brandDeep,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
                if (row.distanceKm != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${row.distanceKm!.round()} km',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: palette.inkMuted),
                  ),
                ],
                const Spacer(),
                if (next != null)
                  _CountdownBadge(
                    minutesUntil: next.minutesUntil,
                    palette: palette,
                    theme: theme,
                  ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              _titleCase(row.destination),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Divider(height: 1, color: palette.hairline),
          ),
          if (upcoming.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UPCOMING',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.inkMuted,
                      letterSpacing: 1.0,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: upcoming.asMap().entries.map((e) {
                      final d = e.value;
                      final isFirst = e.key == 0;
                      return _TimeChip(
                        clock: Schedule.formatClock(d.minuteOfDay),
                        relativeLabel: isFirst
                            ? Schedule.formatDuration(d.minutesUntil)
                            : null,
                        highlight: isFirst || d.minutesUntil <= 30,
                        palette: palette,
                        theme: theme,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          if (passed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Row(
                children: passed
                    .map((d) => Padding(
                          padding:
                              const EdgeInsets.only(right: AppSpacing.sm),
                          child: Text(
                            Schedule.formatClock(d.minuteOfDay),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.inkFaint,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: palette.inkFaint,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split(RegExp(r'\s+'))
          .map((w) => w.isEmpty
              ? w
              : w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────

class _CountdownBadge extends StatelessWidget {
  final int minutesUntil;
  final AppPalette palette;
  final ThemeData theme;
  const _CountdownBadge(
      {required this.minutesUntil,
      required this.palette,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    final imminent = minutesUntil <= 5;
    final soon = minutesUntil <= 30;
    final bg = imminent
        ? palette.danger
        : soon
            ? palette.accent
            : palette.brandLight;
    final fg = imminent
        ? Colors.white
        : soon
            ? palette.onBrand
            : palette.brandDeep;
    final label = minutesUntil <= 0
        ? 'Now'
        : minutesUntil < 60
            ? '${minutesUntil}m'
            : '${minutesUntil ~/ 60}h ${minutesUntil % 60}m';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.access_time_rounded, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TimeChip extends StatelessWidget {
  final String clock;
  final String? relativeLabel;
  final bool highlight;
  final AppPalette palette;
  final ThemeData theme;

  const _TimeChip({
    required this.clock,
    required this.highlight,
    required this.palette,
    required this.theme,
    this.relativeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: highlight ? palette.brandLight : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: highlight ? palette.brand : palette.hairline,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            clock,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: highlight ? palette.brandDeep : palette.ink,
              letterSpacing: 0.5,
            ),
          ),
          if (relativeLabel != null) ...[
            const SizedBox(height: 1),
            Text(
              relativeLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: palette.brand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
