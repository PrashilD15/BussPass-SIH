import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/features/dashboard/presentation/tabs/home_tab.dart';
import 'package:busspass/features/dashboard/presentation/tabs/map_tab.dart';
import 'package:busspass/features/dashboard/presentation/tabs/passes_tab.dart';
import 'package:busspass/features/dashboard/presentation/tabs/profile_tab.dart';
import 'package:busspass/core/ui/responsive_wrapper.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/features/state/presentation/privacy_consent_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  void _onTabTapped(int index) {
    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
    }
  }

  void _navigateToMap() {
    _onTabTapped(1);
  }

  void _navigateToPasses() {
    _onTabTapped(2);
  }

  void _navigateToProfile() {
    _onTabTapped(3);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      if (!settings.hasSeenPrivacyConsent) {
        PrivacyConsentDialog.show(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Held for the lifetime of the authenticated session so travel-pattern
    // boarding reminders re-schedule whenever plans, settings, or history move.
    ref.watch(travelPatternAlertsProvider);

    return ResponsiveWrapper(
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeTab(
              onNavigateToMap: _navigateToMap,
              onNavigateToPasses: _navigateToPasses,
              onNavigateToProfile: _navigateToProfile,
            ),
            const MapTab(),
            const PassesTab(),
            const ProfileTab(),
          ],
        ),
        bottomNavigationBar: _FloatingBottomNav(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Pill Bottom Navigation
// ─────────────────────────────────────────────────────────────────────────────
// A signature premium nav bar: floating above the bottom with a soft shadow,
// rounded pill shape, and a clear animated active indicator. Feels modern and
// elevated without being flashy.

class _FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FloatingBottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItemData(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: 'Home',
    ),
    _NavItemData(
      icon: Icons.map_outlined,
      activeIcon: Icons.map_rounded,
      label: 'Map',
    ),
    _NavItemData(
      icon: Icons.confirmation_num_outlined,
      activeIcon: Icons.confirmation_num_rounded,
      label: 'Passes',
    ),
    _NavItemData(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm + 2),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: palette.hairline),
          boxShadow: AppShadow.floating(Colors.black),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = currentIndex == i;
              return _PillNavItem(
                item: item,
                isActive: isActive,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _PillNavItem extends StatelessWidget {
  final _NavItemData item;
  final bool isActive;
  final VoidCallback onTap;

  const _PillNavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? palette.brandLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              size: 26,
              color: isActive ? palette.brand : palette.inkMuted,
            )
            .animate(target: isActive ? 1 : 0)
            .scaleXY(begin: 0.9, end: 1.1, duration: 250.ms, curve: Curves.easeOutBack)
            .tint(color: palette.brand, end: 1.0),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? palette.brand : palette.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
