/// Home tab — the spine of the app.
///
/// Every number and row on this screen is real: stats come from the rider's
/// actual travel totals, the quick chips are their saved home/work places,
/// route shortcuts are their genuinely-frequent searches, and the nearby-stands
/// list is the live network around their GPS position. The old version showed
/// hardcoded zeros, a disabled "Buy Pass", and a "No active journey" card that
/// could never change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/core/services/state_detection_service.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/features/journey/presentation/journey_search_screen.dart';
import 'package:busspass/features/journey/presentation/live_navigation_screen.dart';
import 'package:busspass/features/journey/presentation/tracking_itinerary.dart';
import 'package:busspass/features/state/presentation/state_switcher_sheet.dart';
import 'package:busspass/features/timetable/presentation/timetables_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class HomeTab extends ConsumerWidget {
  final VoidCallback onNavigateToMap;
  final VoidCallback onNavigateToPasses;
  final VoidCallback onNavigateToProfile;

  const HomeTab({
    super.key,
    required this.onNavigateToMap,
    required this.onNavigateToPasses,
    required this.onNavigateToProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final firstName = user?.displayName?.split(' ').first ?? 'Traveler';
    final greeting = _greeting();
    final locale = Localizations.localeOf(context);

    final activeTicket = ref.watch(activeTicketProvider);
    final totals = ref.watch(travelTotalsProvider);
    final tickets = ref.watch(ticketBucketsProvider);
    final history = ref.watch(journeyHistoryProvider);
    final frequent = ref.watch(frequentSearchesProvider);

    final activePasses =
        tickets.live.where((t) => t.isPass).length;

    var section = 0;

    return Scaffold(
      backgroundColor: context.palette.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.pageInset,
              AppSpacing.xl, AppSpacing.pageInset, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              _Header(
                greeting: greeting,
                name: firstName,
                userInitial:
                    user?.displayName?.substring(0, 1).toUpperCase(),
                locale: locale,
                onNotifications: () =>
                    _showNotificationsSheet(context, ref, activeTicket),
              ).staggerIn(section++),

              const SizedBox(height: AppSpacing.xl),

              // ── "You appear to be aboard" — the dormant detector surfaced ─
              const _BoardingPrompt().staggerIn(section++),

              // ── Active ticket — only when there genuinely is one ─────
              if (activeTicket != null) ...[
                _ActiveTicketBanner(
                  ticket: activeTicket,
                  onViewPasses: onNavigateToPasses,
                ).staggerIn(section++),
                const SizedBox(height: AppSpacing.xl),
              ],

              // ── STC banner ───────────────────────────────────────────
              const _ActiveSTCBanner().staggerIn(section++),

              const SizedBox(height: AppSpacing.lg),

              // ── Search hero + saved places ───────────────────────────
              _SearchHero(onTap: () => _openSearch(context)).staggerIn(section++),
              const SizedBox(height: AppSpacing.md),
              const _SavedPlaceChips().staggerIn(section++),

              const SizedBox(height: AppSpacing.xxl),

              // ── Real travel stats ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.receipt_long_outlined,
                      value: '${totals.journeys}',
                      label: 'home.trips'.tr(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.route_outlined,
                      value: '${totals.distanceKm.round()} km',
                      label: 'home.km_travelled'.tr(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.confirmation_num_outlined,
                      value: '$activePasses',
                      label: 'home.active_passes'.tr(),
                    ),
                  ),
                ],
              ).staggerIn(section++),

              const SizedBox(height: AppSpacing.xxl),

              // ── Quick actions — all wired ────────────────────────────
              SectionHeader(title: 'home.quick_actions'.tr())
                  .staggerIn(section++),
              const SizedBox(height: AppSpacing.md),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.9,
                children: [
                  _QuickAction(
                    icon: Icons.map_outlined,
                    label: 'home.live_map'.tr(),
                    onTap: onNavigateToMap,
                  ),
                  _QuickAction(
                    icon: Icons.schedule_outlined,
                    label: 'home.timetables'.tr(),
                    onTap: () => _openTimetables(context),
                  ),
                  _QuickAction(
                    icon: Icons.confirmation_number_outlined,
                    label: 'home.my_passes'.tr(),
                    onTap: onNavigateToPasses,
                  ),
                  _QuickAction(
                    icon: Icons.settings_outlined,
                    label: 'home.profile'.tr(),
                    onTap: onNavigateToProfile,
                  ),
                ],
              ).staggerIn(section++),

              // ── Frequent routes, only if they exist ──────────────────
              if (frequent.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                SectionHeader(
                  title: 'home.frequent_routes'.tr(),
                  subtitle: 'home.frequent_hint'.tr(),
                ).staggerIn(section++),
                const SizedBox(height: AppSpacing.md),
                _FrequentRoutesList(routes: frequent)
                    .staggerIn(section++),
              ],

              // ── Nearby stands with next departures ───────────────────
              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(title: 'home.nearby_stands'.tr())
                  .staggerIn(section++),
              const SizedBox(height: AppSpacing.md),
              const _NearbyStopsList().staggerIn(section++),

              // History hint — real count, not a zero placeholder.
              if (history.isEmpty && frequent.isEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                AppBanner(
                  icon: Icons.explore_outlined,
                  tone: AppBannerTone.brand,
                  title: 'home.first_journey_title'.tr(),
                  message: 'home.first_journey_msg'.tr(),
                ).staggerIn(section++),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openSearch(BuildContext context, {dynamic initialOrigin}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            JourneySearchScreen(initialOrigin: initialOrigin),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  void _openTimetables(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const TimetablesScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'home.greeting_morning'.tr();
    if (h < 17) return 'home.greeting_afternoon'.tr();
    return 'home.greeting_evening'.tr();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications sheet
// ─────────────────────────────────────────────────────────────────────────────

void _showNotificationsSheet(
    BuildContext context, WidgetRef ref, Ticket? activeTicket) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return Container(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl)),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm,
            AppSpacing.xl, AppSpacing.xxl),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.hairlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'home.notifications'.tr(),
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (activeTicket != null)
                AppBanner(
                  icon: Icons.notifications_active_rounded,
                  tone: AppBannerTone.brand,
                  title: activeTicket.routeLabel,
                  message:
                      '${'home.departs_at'.tr()} ${DateFormat('jm · d MMM').format(activeTicket.departsAt)}',
                )
              else
                EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'home.alerts_empty_title'.tr(),
                  message: 'home.alerts_empty_msg'.tr(),
                ),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Active ticket
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveTicketBanner extends ConsumerWidget {
  final Ticket ticket;
  final VoidCallback onViewPasses;

  const _ActiveTicketBanner(
      {required this.ticket, required this.onViewPasses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider);
    final minutesTo = ticket.minutesUntilDeparture(now);
    final isPass = ticket.isPass;

    final progress = isPass && ticket.validFrom != null && ticket.validUntil != null
        ? (now.difference(ticket.validFrom!).inMilliseconds /
                ticket.validUntil!.difference(ticket.validFrom!).inMilliseconds)
            .clamp(0.0, 1.0)
        : null;

    return AppCard(
      raised: true,
      borderColor: palette.brand.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TagChip.tone(context,
                  isPass ? 'home.pass'.tr() : 'home.journey'.tr(),
                  icon: isPass
                      ? Icons.credit_card_rounded
                      : Icons.directions_bus_rounded,
                  tone: AppBannerTone.brand),
              const Spacer(),
              if (!isPass)
                Text(
                  minutesTo > 0
                      ? 'home.leaves_in'.tr(
                          namedArgs: {'minutes': '$minutesTo'})
                      : 'home.boarding_now'.tr(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: minutesTo > 0 ? palette.warning : palette.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            ticket.routeLabel,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            ticket.serviceClassKey,
            style: theme.textTheme.bodySmall,
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            JourneyProgressBar(
              progress: progress,
              startLabel: 'home.valid_from'.tr(),
              endLabel: 'home.valid_until'.tr(),
              centreLabel: '${(progress * 100).round()}%',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'home.view_passes'.tr(),
            icon: Icons.confirmation_num_rounded,
            iconTrailing: true,
            onPressed: onViewPasses,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String greeting;
  final String name;
  final String? userInitial;
  final Locale locale;
  final VoidCallback onNotifications;

  const _Header({
    required this.greeting,
    required this.name,
    required this.userInitial,
    required this.locale,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                name,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        _HeaderCircle(
          onTap: () => _showLanguagePicker(context),
          badge: _localeCode(locale.languageCode),
          child: Text(
            userInitial ?? 'T',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.brandDeep,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _HeaderCircle(
          onTap: onNotifications,
          child: Icon(Icons.notifications_outlined,
              color: palette.inkSoft, size: 22),
        ),
      ],
    );
  }

  static String _localeCode(String code) => switch (code) {
        'mr' => 'अ',
        'hi' => 'अ',
        'kn' => 'ಅ',
        _ => 'A',
      };
}

class _HeaderCircle extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? badge;

  const _HeaderCircle({
    required this.child,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.surface,
              shape: BoxShape.circle,
              border: Border.all(color: palette.hairline),
            ),
            child: Center(child: child),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: palette.brand,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(color: palette.canvas, width: 2),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: palette.onBrand,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void _showLanguagePicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.palette.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl)),
    ),
    builder: (context) {
      final currentLocale = context.locale.languageCode;
      final options = [
        ('en', 'English', 'A'),
        ('mr', 'मराठी (Marathi)', 'अ'),
        ('hi', 'हिंदी (Hindi)', 'अ'),
        ('kn', 'ಕನ್ನಡ (Kannada)', 'ಅ'),
      ];
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(
              'home.select_language'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (code, label, _) in options)
              ListTile(
                title: Text(label),
                trailing: currentLocale == code
                    ? Icon(Icons.check, color: context.palette.brand)
                    : null,
                onTap: () {
                  context.setLocale(Locale(code));
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Search hero — sanctioned gradientBrand, one per screen
// ─────────────────────────────────────────────────────────────────────────────

class _SearchHero extends ConsumerWidget {
  final VoidCallback onTap;
  const _SearchHero({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final network = ref.watch(networkProvider).value;
    final places = ref.watch(savedPlacesProvider);

    SavedPlace? placeOf(SavedPlaceKind kind) {
      for (final p in places) {
        if (p.kind == kind) return p;
      }
      return null;
    }

    final home = placeOf(SavedPlaceKind.home);
    final work = placeOf(SavedPlaceKind.work);

    Widget chip(SavedPlace? place, String label, IconData icon) {
      final stop =
          place == null || network == null ? null : network.stopById(place.stopId);
      return GestureDetector(
        onTap: stop == null ? null : () => _searchFrom(context, stop),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppSpacing.brPill,
            border: Border.all(color: palette.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15,
                  color: stop == null ? palette.inkFaint : palette.accent),
              const SizedBox(width: AppSpacing.xs + 1),
              Text(
                stop?.city ?? label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: stop == null ? palette.inkMuted : palette.ink,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: palette.gradientBrand,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: AppShadow.glowBrand(palette.brand),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.onBrand.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(Icons.search_rounded,
                      color: palette.onBrand, size: 22),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'home.search_title'.tr(),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: palette.onBrand,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'home.search_subtitle'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  palette.onBrand.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: palette.onBrand.withValues(alpha: 0.65), size: 16),
              ],
            ),
          ),
        ),
        // Saved places only surface when they actually resolve to stops on the
        // active network; no invented "Saved place" rows.
        if (home != null || work != null) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              chip(home, 'home.save_home'.tr(), Icons.home_outlined),
              chip(work, 'home.save_work'.tr(), Icons.work_outline_rounded),
            ],
          ),
        ],
      ],
    );
  }

  void _searchFrom(BuildContext context, dynamic stop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JourneySearchScreen(initialOrigin: stop),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved place affordance — shown only when the rider has none
// ─────────────────────────────────────────────────────────────────────────────

class _SavedPlaceChips extends ConsumerWidget {
  const _SavedPlaceChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(savedPlacesProvider);
    if (places.isNotEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        'home.save_places_hint'.tr(),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: palette.inkMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat card — real values
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.brand),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick action
// ─────────────────────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: AppShadow.card(Colors.black),
              border: Border.all(color: palette.hairline),
            ),
            child: Icon(icon, color: palette.brand, size: 24),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.inkSoft,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frequent routes — real repeat searches, tap to re-run one
// ─────────────────────────────────────────────────────────────────────────────

class _FrequentRoutesList extends ConsumerWidget {
  final List<RecentSearch> routes;
  const _FrequentRoutesList({required this.routes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final network = ref.watch(networkProvider).value;
    if (network == null) return const SkeletonList(count: 2);

    // Only offer routes whose stops exist on the *active* network — a frequent
    // search from another state would otherwise be a broken tap.
    final usable = routes.where((r) {
      return network.stopById(r.originStopId) != null &&
          network.stopById(r.destinationStopId) != null;
    }).take(6).toList();
    if (usable.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: usable.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final r = usable[i];
          return GestureDetector(
            onTap: () {
              final origin = network.stopById(r.originStopId)!;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      JourneySearchScreen(initialOrigin: origin),
                ),
              );
            },
            child: Container(
              width: 168,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: palette.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.trending_up_rounded,
                          size: 14, color: palette.accent),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          '${r.originName} → ${r.destinationName}',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'home.searched_n_times'
                        .tr(namedArgs: {'count': '${r.count}'}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nearby stands — real GPS neighbourhood, honest denial state
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyStopsList extends ConsumerWidget {
  const _NearbyStopsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final nearbyAsync = ref.watch(nearbyStopsProvider);

    return nearbyAsync.when(
      loading: () => const SkeletonList(count: 2, variant: SkeletonVariant.listTile),
      error: (_, _) => Text(
        'home.nearby_unavailable'.tr(),
        style: theme.textTheme.bodySmall,
      ),
      data: (nearby) {
        if (nearby.isEmpty) {
          return Text(
            'home.nearby_none'.tr(),
            style: theme.textTheme.bodySmall,
          );
        }
        final top = nearby.take(4).toList();
        return Column(
          children: [
            for (final entry in top)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: palette.brandLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.location_on_outlined,
                            color: palette.brand, size: 19),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.stop.name.isEmpty
                                  ? entry.stop.city
                                  : entry.stop.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${entry.distanceKm < 1 ? '${(entry.distanceKm * 1000).round()} m' : '${entry.distanceKm.toStringAsFixed(1)} km'} · ${entry.stop.city}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _StopDepartureBadge(stopId: entry.stop.id),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "3 buses today · next 14:35" — the stop's real departure board, compacted.
class _StopDepartureBadge extends ConsumerWidget {
  final String stopId;
  const _StopDepartureBadge({required this.stopId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final departures = ref.watch(departuresFromStopProvider(stopId));

    return departures.when(
      loading: () => const SkeletonBox(width: 74, height: 14),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Text('home.no_departures'.tr(),
              style: theme.textTheme.labelSmall);
        }
        final next = list.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              next.next.minutesUntil <= 0
                  ? 'home.leaving_now'.tr()
                  : '${next.next.minutesUntil} min',
              style: theme.textTheme.labelMedium?.copyWith(
                color: next.next.minutesUntil <= 30
                    ? palette.success
                    : palette.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              Schedule.formatClock24(next.next.minuteOfDay),
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boarding prompt — the transit detector surfaced.
//
// When the detector's inference is confident the rider is aboard a specific
// bus (sustained speed + corridor + trail match), offer one-tap live tracking,
// so tracking never depends on the rider having found the bus on the map.
// Gated behind a per-session dismissal so a false positive can't nag.
// ─────────────────────────────────────────────────────────────────────────────

class _BoardingPrompt extends ConsumerWidget {
  const _BoardingPrompt();

  static const double _minConfidence = 0.55;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detection = ref.watch(transitDetectionProvider).value;
    if (detection == null) return const SizedBox.shrink();

    final dismissed = ref.watch(boardingPromptDismissedAtProvider);
    if (dismissed != null &&
        DateTime.now().difference(dismissed) <
            const Duration(minutes: 45)) {
      return const SizedBox.shrink();
    }

    // Only assert boarding for a high-confidence specific-bus match. A mere
    // "possibly on bus" would nag riders in cars; the cost of a wrong prompt
    // is higher than the benefit of an early one.
    final bus = detection.bus;
    if (bus == null || !detection.isOnBoard || detection.confidence < _minConfidence) {
      return const SizedBox.shrink();
    }

    final network = ref.watch(networkProvider).value;
    if (network == null) return const SizedBox.shrink();
    final route = network.routeById(bus.routeId);
    if (route == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppBanner(
        icon: Icons.location_on_rounded,
        tone: AppBannerTone.success,
        title: 'live.board_prompt'.tr(),
        message: '${bus.busType} · ${route.originCity} → ${route.destinationCity}',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'live.board_not_me'.tr(),
              onPressed: () => ref
                  .read(boardingPromptDismissedAtProvider.notifier)
                  .dismiss(),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
            PrimaryButton(
              label: 'live.board_start'.tr(),
              expand: false,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveNavigationScreen(
                      itinerary: buildTrackingItinerary(network, route, bus),
                      legIndex: 0,
                      busId: bus.id,
                    ),
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
// Active STC banner — rebuilt on the shared STCBadge
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveSTCBanner extends ConsumerWidget {
  const _ActiveSTCBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the *effective* STC so a manual state switch updates the banner,
    // but show the shimmer while GPS detection is still resolving with no
    // explicit choice made yet.
    final selected = ref.watch(selectedSTCProvider);
    final detectedAsync = ref.watch(detectedSTCProvider);
    final stc = selected ?? detectedAsync.value;

    if (stc == null) {
      return const Shimmer(
        child: SkeletonBox(height: 62, borderRadius: AppSpacing.brMd),
      );
    }
    return GestureDetector(
      onTap: () => showStateSwitcher(context),
      behavior: HitTestBehavior.opaque,
      child: _build(context, stc),
    );
  }

  Widget _build(BuildContext context, DetectedSTC stc) {
    final palette = context.palette;
    final color = Color(stc.badgeColor);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.06),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          STCBadge(stc: stc, size: 44),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stc.stcCode,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_outlined,
                        size: 12, color: palette.inkMuted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${stc.stateName} State Road Transport',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          LivePulse(label: 'home.connected'.tr()),
        ],
      ),
    );
  }
}
