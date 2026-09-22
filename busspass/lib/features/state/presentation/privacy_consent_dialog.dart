import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
import 'package:busspass/data/providers/app_providers.dart';

class PrivacyConsentDialog extends ConsumerWidget {
  const PrivacyConsentDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PrivacyConsentDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brLg),
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: palette.brand),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'privacy.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.translate_rounded),
            color: palette.inkSoft,
            tooltip: 'Translate',
            onPressed: () {
              final locales = context.supportedLocales;
              final current = context.locale;
              final index = locales.indexOf(current);
              final next = locales[(index + 1) % locales.length];
              context.setLocale(next);
            },
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'privacy.consent_message'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _buildFeatureRow(
              context,
              icon: Icons.history,
              title: 'privacy.recent_searches'.tr(),
              description: 'privacy.recent_searches_desc'.tr(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildFeatureRow(
              context,
              icon: Icons.location_on_outlined,
              title: 'privacy.location_services'.tr(),
              description: 'privacy.location_services_desc'.tr(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'privacy.change_anytime'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.inkSoft,
                  ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            ref.read(settingsProvider.notifier).setDataCollectionConsent(false);
            ref.read(settingsProvider.notifier).setHasSeenPrivacyConsent(true);
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          ),
          child: Text('privacy.decline'.tr(), style: TextStyle(color: palette.danger)),
        ),
        FilledButton(
          onPressed: () {
            ref.read(settingsProvider.notifier).setDataCollectionConsent(true);
            ref.read(settingsProvider.notifier).setHasSeenPrivacyConsent(true);
            Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: palette.brand,
            foregroundColor: palette.onBrand,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          ),
          child: Text('privacy.accept'.tr()),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.palette.inkSoft),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.inkSoft,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
