import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/features/journey/presentation/journey_search_screen.dart';
import 'package:busspass/features/timetable/presentation/timetables_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
class HomeTab extends ConsumerWidget {
  final VoidCallback onNavigateToMap;

  const HomeTab({super.key, required this.onNavigateToMap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final firstName = user?.displayName?.split(' ').first ?? 'Traveler';
    final greeting = _greeting();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          firstName,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showLanguagePicker(context),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: const Center(
                            child: Text(
                              'A/अ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.inkSoft,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.08),

              const SizedBox(height: AppSpacing.xxl),

              // ── Primary Action: Search ─────────────────────────────────
              _SearchBanner(
                onTap: () => _openSearch(context),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.08),

              const SizedBox(height: AppSpacing.xxl),

              // ── Quick Actions ──────────────────────────────────────────
              SectionHeader(
                title: 'home.quick_actions'.tr(),
                actionLabel: 'All',
                onAction: () {},
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickAction(
                    icon: Icons.map_outlined,
                    label: 'home.live_map'.tr(),
                    onTap: onNavigateToMap,
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.08),
                  _QuickAction(
                    icon: Icons.schedule_outlined,
                    label: 'home.timetables'.tr(),
                    onTap: () => _openTimetables(context),
                  ).animate().fadeIn(delay: 380.ms).slideY(begin: 0.08),
                  _QuickAction(
                    icon: Icons.confirmation_number_outlined,
                    label: 'home.buy_pass'.tr(),
                    onTap: () {},
                  ).animate().fadeIn(delay: 460.ms).slideY(begin: 0.08),
                  _QuickAction(
                    icon: Icons.wallet_outlined,
                    label: 'home.my_passes'.tr(),
                    onTap: () {},
                  ).animate().fadeIn(delay: 540.ms).slideY(begin: 0.08),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── Active Journey ───────────────────────────────────────
              SectionHeader(
                title: 'home.your_journeys'.tr(),
                actionLabel: null,
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.brandLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: AppColors.brand,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No active journey',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Your live tickets will appear here',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkMuted.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.08),
            ],
          ),
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const JourneySearchScreen(),
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

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (context) {
        final currentLocale = context.locale.languageCode;
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
              ListTile(
                title: const Text('English'),
                trailing: currentLocale == 'en' ? const Icon(Icons.check, color: AppColors.brand) : null,
                onTap: () {
                  context.setLocale(const Locale('en'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('मराठी (Marathi)'),
                trailing: currentLocale == 'mr' ? const Icon(Icons.check, color: AppColors.brand) : null,
                onTap: () {
                  context.setLocale(const Locale('mr'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('हिंदी (Hindi)'),
                trailing: currentLocale == 'hi' ? const Icon(Icons.check, color: AppColors.brand) : null,
                onTap: () {
                  context.setLocale(const Locale('hi'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('ಕನ್ನಡ (Kannada)'),
                trailing: currentLocale == 'kn' ? const Icon(Icons.check, color: AppColors.brand) : null,
                onTap: () {
                  context.setLocale(const Locale('kn'));
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
}

class _SearchBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Colors.white, size: 26),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'home.search_title'.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'home.search_subtitle'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, color: AppColors.inkSoft, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}