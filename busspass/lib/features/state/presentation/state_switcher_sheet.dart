/// StateSwitcherSheet — let the rider pick which state transport network to
/// ride. GPS auto-detection is the default, but a user standing near a state
/// border (or with location denied) needs an explicit override.
///
/// Selecting a state persists the choice and re-keys [effectiveSTCProvider],
/// which cascades through the whole network chain: graph, planner, stops,
/// departures, and the simulator all rebuild.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:busspass/core/services/state_detection_service.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

/// Show the switcher. Returns the chosen STC, or null if dismissed.
Future<DetectedSTC?> showStateSwitcher(BuildContext context) {
  return showModalBottomSheet<DetectedSTC>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StateSwitcherSheet(),
  );
}

class _StateSwitcherSheet extends ConsumerWidget {
  const _StateSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final effective = ref.watch(effectiveSTCProvider);
    final selected = ref.watch(selectedSTCProvider);
    final detected = ref.watch(detectedSTCProvider).value;

    return AppSheet(
      title: 'state.switch_title'.tr(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'state.switch_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final stc in kAllSTCs)
            _StateRow(
              stc: stc,
              isActive: stc.stcCode == effective.stcCode,
              isExplicit: selected?.stcCode == stc.stcCode,
              isDetected: detected?.stcCode == stc.stcCode,
              brandColor: Color(stc.badgeColor),
              onTap: () async {
                await ref.read(selectedSTCProvider.notifier).select(stc);
                if (context.mounted) {
                  Navigator.pop(context, stc);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'state.switched'.tr(namedArgs: {
                          'stc': stc.stcCode,
                          'state': stc.stateName
                        }),
                      ),
                    ),
                  );
                }
              },
            ),

          // Follow-GPS option, only when the rider previously overrode.
          if (selected != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: palette.hairline),
            ListTile(
              leading: Icon(Icons.gps_fixed_rounded, color: palette.brand),
              title: Text('state.follow_gps'.tr()),
              subtitle: Text('state.follow_gps_hint'.tr()),
              onTap: () async {
                await ref.read(selectedSTCProvider.notifier).clear();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  final DetectedSTC stc;
  final bool isActive;
  final bool isExplicit;
  final bool isDetected;
  final Color brandColor;
  final VoidCallback onTap;

  const _StateRow({
    required this.stc,
    required this.isActive,
    required this.isExplicit,
    required this.isDetected,
    required this.brandColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isActive
                ? brandColor.withValues(alpha: 0.10)
                : palette.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color:
                  isActive ? brandColor.withValues(alpha: 0.5) : palette.hairline,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              STCBadge(stc: stc, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          stc.stcCode,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: brandColor,
                                  fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        if (isDetected && !isExplicit)
                          TagChip(
                            label: 'state.via_gps'.tr(),
                            icon: Icons.location_on_rounded,
                            dense: true,
                            foreground: palette.brandDeep,
                            background: palette.brandLight,
                          ),
                      ],
                    ),
                    Text(
                      stc.stateName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.check_circle_rounded, color: brandColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
