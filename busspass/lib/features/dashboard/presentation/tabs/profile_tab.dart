/// Profile — real settings pages, every row goes somewhere.
///
/// The old tab had ~7 no-op rows with a hardcoded "English" subtitle. Each
/// preference here maps to a field on [AppSettings] (persisted through
/// [SettingsNotifier]) and changes the app's behaviour: concession category
/// reprices fares, journey preference re-ranks the planner, and saved places
/// feed the home screen's quick chips.
library;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/data/repositories/local_store.dart';
import 'package:busspass/features/state/presentation/state_switcher_sheet.dart';
import 'package:busspass/theme/widgets/brand_mark.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/features/state/presentation/privacy_consent_dialog.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final savedPlaces = ref.watch(savedPlacesProvider);
    final history = ref.watch(journeyHistoryProvider);

    String languageLabel(String code) => switch (code) {
          'mr' => 'मराठी',
          'hi' => 'हिंदी',
          'kn' => 'ಕನ್ನಡ',
          _ => 'English',
        };

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: Text('profile.title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageInset, AppSpacing.sm, AppSpacing.pageInset, 120),
        children: [
          _ProfileHeader(
            name: user?.displayName ?? 'User',
            email: user?.email ?? '',
            initial: user?.displayName?.substring(0, 1).toUpperCase(),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Concession ──────────────────────────────────────────────
          SectionHeader(title: 'profile.concession'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.badge_outlined,
                title: 'profile.rider_category'.tr(),
                subtitle: settings.riderCategory.label,
                trailing: Text(
                  '-${settings.riderCategory.discountPercent}%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.success,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                onTap: () => _pickRiderCategory(context, ref),
              ),
              SettingsRow(
                icon: Icons.tune_rounded,
                title: 'profile.journey_pref'.tr(),
                subtitle: _preferenceLabel(settings.journeyPreference),
                onTap: () => _pickJourneyPreference(context, ref),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Saved places ────────────────────────────────────────────
          SectionHeader(title: 'profile.saved_places'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              for (final kind in SavedPlaceKind.values)
                _SavedPlaceRow(kind: kind, places: savedPlaces),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Travel ──────────────────────────────────────────────────
          SectionHeader(title: 'profile.travel'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.receipt_long_outlined,
                title: 'profile.booking_history'.tr(),
                subtitle: history.isEmpty
                    ? 'profile.no_history'.tr()
                    : 'profile.n_trips'
                        .tr(namedArgs: {'count': '${history.length}'}),
                onTap: history.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const _HistoryScreen()),
                      ),
              ),
              const _EmergencyContactRow(),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Preferences ─────────────────────────────────────────────
          SectionHeader(title: 'profile.preferences'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.language_rounded,
                title: 'profile.language'.tr(),
                subtitle: languageLabel(context.locale.languageCode),
                onTap: () => _showLanguagePicker(context),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final stc = ref.watch(effectiveSTCProvider);
                  return SettingsRow(
                    icon: Icons.alt_route_rounded,
                    title: 'profile.network'.tr(),
                    subtitle: '${stc.stcCode} · ${stc.stateName}',
                    onTap: () => showStateSwitcher(context),
                  );
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final hasConsent = ref.watch(settingsProvider.select((s) => s.dataCollectionConsent));
                  return SettingsRow(
                    icon: Icons.data_usage_rounded,
                    title: 'Data Collection Consent',
                    subtitle: hasConsent ? 'Granted' : 'Revoked',
                    onTap: () {
                      PrivacyConsentDialog.show(context);
                    },
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Notifications ───────────────────────────────────────────
          SectionHeader(title: 'profile.notifications'.tr()),
          const SizedBox(height: AppSpacing.sm),
          const _NotificationSettings(),

          const SizedBox(height: AppSpacing.xxl),

          // ── Appearance ──────────────────────────────────────────────
          SectionHeader(title: 'profile.appearance'.tr()),
          const SizedBox(height: AppSpacing.sm),
          const _AppearanceCard(),

          const SizedBox(height: AppSpacing.xxl),

          // ── Support ─────────────────────────────────────────────────
          SectionHeader(title: 'profile.support'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.headset_mic_outlined,
                title: 'Contact Us',
                subtitle: 'Request a callback or leave a message',
                onTap: () => _showContactUs(context),
              ),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: 'profile.about'.tr(),
                subtitle: 'profile.about_subtitle'.tr(),
                onTap: () => _showAbout(context),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Account ─────────────────────────────────────────────────
          SectionHeader(title: 'profile.account'.tr()),
          const SizedBox(height: AppSpacing.sm),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'profile.logout'.tr(),
                onTap: () => _confirmLogout(context, ref),
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _preferenceLabel(String name) => switch (name) {
        'cheapest' => 'profile.pref_cheapest'.tr(),
        'fewestChanges' => 'profile.pref_fewest'.tr(),
        'earliestArrival' => 'profile.pref_earliest'.tr(),
        _ => 'profile.pref_fastest'.tr(),
      };

  void _showContactUs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ContactUsSheet(),
    );
  }
}

class _ContactUsSheet extends ConsumerStatefulWidget {
  const _ContactUsSheet();
  @override
  ConsumerState<_ContactUsSheet> createState() => _ContactUsSheetState();
}

class _ContactUsSheetState extends ConsumerState<_ContactUsSheet> {
  final _phoneController = TextEditingController();
  final _queryController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final query = _queryController.text.trim();
    if (phone.isEmpty && query.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      final firestore = ref.read(firestoreProvider);
      
      if (firestore != null) {
        await firestore.collection('support_queries').add({
          'uid': user?.uid,
          'email': user?.email,
          'phone': phone,
          'query': query,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'open',
        });
      }
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your request has been submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit request.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(
        bottom: insets.bottom + AppSpacing.xl,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.headset_mic_outlined, color: palette.brand),
              const SizedBox(width: AppSpacing.sm),
              Text('Contact Support',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Request a callback or leave a message for our support team.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile Number (for callback)',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(borderRadius: AppSpacing.brMd),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _queryController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'How can we help?',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: AppSpacing.brMd),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                backgroundColor: palette.brand,
                foregroundColor: palette.onBrand,
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit Request'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? initial;

  const _ProfileHeader({
    required this.name,
    required this.email,
    this.initial,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: palette.gradientBrand,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: palette.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial ?? 'U',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.brand,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  email.isEmpty ? 'profile.guest'.tr() : email,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rider category picker
// ─────────────────────────────────────────────────────────────────────────────

void _pickRiderCategory(BuildContext context, WidgetRef ref) {
  final current = ref.read(settingsProvider).riderCategory;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => AppSheet(
      title: 'profile.pick_category'.tr(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final category in RiderCategory.values)
            ListTile(
              leading: Icon(
                category == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: category == current
                    ? sheetContext.palette.brand
                    : sheetContext.palette.inkFaint,
              ),
              title: Text(category.label),
              subtitle: category.discountPercent == 0
                  ? null
                  : Text('profile.concession_pct'.tr(
                      namedArgs: {'pct': '${category.discountPercent}'})),
              onTap: () {
                ref.read(settingsProvider.notifier).setRiderCategory(category);
                Navigator.pop(sheetContext);
              },
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

void _pickJourneyPreference(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(settingsProvider.notifier);
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => AppSheet(
      title: 'profile.pick_preference'.tr(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final pref in JourneyPreference.values)
            ListTile(
              leading: Icon(switch (pref) {
                JourneyPreference.fastest => Icons.bolt_rounded,
                JourneyPreference.cheapest => Icons.savings_rounded,
                JourneyPreference.fewestChanges => Icons.swap_horiz_rounded,
                JourneyPreference.earliestArrival =>
                  Icons.schedule_rounded,
              }),
              title: Text(switch (pref) {
                JourneyPreference.fastest => 'profile.pref_fastest'.tr(),
                JourneyPreference.cheapest => 'profile.pref_cheapest'.tr(),
                JourneyPreference.fewestChanges => 'profile.pref_fewest'.tr(),
                JourneyPreference.earliestArrival =>
                  'profile.pref_earliest'.tr(),
              }),
              trailing: pref.name ==
                      ref.read(settingsProvider).journeyPreference
                  ? Icon(Icons.check_rounded,
                      color: sheetContext.palette.brand)
                  : null,
              onTap: () {
                notifier.setJourneyPreference(pref);
                Navigator.pop(sheetContext);
              },
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved place row — shows bound stop or "choose" affordance
// ─────────────────────────────────────────────────────────────────────────────

class _SavedPlaceRow extends ConsumerWidget {
  final SavedPlaceKind kind;
  final List<SavedPlace> places;

  const _SavedPlaceRow({required this.kind, required this.places});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SavedPlace? bound;
    for (final p in places) {
      if (p.kind == kind) bound = p;
    }

    return SettingsRow(
      icon: switch (kind) {
        SavedPlaceKind.home => Icons.home_outlined,
        SavedPlaceKind.work => Icons.work_outline_rounded,
        SavedPlaceKind.other => Icons.star_outline_rounded,
      },
      title: switch (kind) {
        SavedPlaceKind.home => 'profile.home_place'.tr(),
        SavedPlaceKind.work => 'profile.work_place'.tr(),
        SavedPlaceKind.other => 'profile.favourite'.tr(),
      },
      subtitle: bound == null
          ? 'profile.not_set'.tr()
          : '${bound.label} · ${bound.stopId}',
      trailing: bound == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'profile.remove'.tr(),
              onPressed: () =>
                  ref.read(savedPlacesProvider.notifier).remove(bound!.id),
            ),
      onTap: bound == null ? () => _pickStopFor(context, ref, kind) : null,
    );
  }

  Future<void> _pickStopFor(
      BuildContext context, WidgetRef ref, SavedPlaceKind kind) async {
    final stop = await showModalBottomSheet<NetworkStop>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StopPickerSheet(title: 'profile.pick_stop'.tr()),
    );
    if (stop == null) return;
    await ref.read(savedPlacesProvider.notifier).save(SavedPlace(
          id: 'sp-${DateTime.now().millisecondsSinceEpoch}',
          stopId: stop.id,
          label: stop.name.isEmpty ? stop.city : stop.name,
          kind: kind,
          savedAt: DateTime.now(),
        ));
  }
}

/// Minimal stop search sheet, reusing [stopSearchProvider].
class _StopPickerSheet extends ConsumerStatefulWidget {
  final String title;
  const _StopPickerSheet({required this.title});

  @override
  ConsumerState<_StopPickerSheet> createState() => _StopPickerSheetState();
}

class _StopPickerSheetState extends ConsumerState<_StopPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final results = _query.trim().length >= 2
        ? ref.watch(stopSearchProvider(_query.trim()))
        : const AsyncValue<List<NetworkStop>>.data([]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'profile.search_stops'.tr(),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: results.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('profile.search_failed'.tr()),
                  ),
                  data: (stops) => stops.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            _query.trim().length < 2
                                ? 'profile.type_to_search'.tr()
                                : 'profile.no_results'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: stops.length,
                          itemBuilder: (context, i) {
                            final stop = stops[i];
                            return ListTile(
                              leading: const Icon(
                                  Icons.location_on_outlined),
                              title: Text(stop.name.isEmpty
                                  ? stop.city
                                  : stop.name),
                              subtitle: Text(stop.city),
                              onTap: () => Navigator.pop(context, stop),
                            );
                          },
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
// Emergency contact
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencyContactRow extends ConsumerStatefulWidget {
  const _EmergencyContactRow();

  @override
  ConsumerState<_EmergencyContactRow> createState() =>
      _EmergencyContactRowState();
}

class _EmergencyContactRowState extends ConsumerState<_EmergencyContactRow> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final has = settings.hasEmergencyContact;

    return SettingsRow(
      icon: Icons.emergency_share_outlined,
      title: 'profile.emergency'.tr(),
      subtitle: has
          ? '${settings.emergencyContactName} · ${settings.emergencyContactPhone}'
          : 'profile.emergency_none'.tr(),
      onTap: () => _editContact(context, settings),
    );
  }

  Future<void> _editContact(
      BuildContext context, AppSettings settings) async {
    final nameCtrl =
        TextEditingController(text: settings.emergencyContactName);
    final phoneCtrl =
        TextEditingController(text: settings.emergencyContactPhone);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: AppSheet(
          title: 'profile.emergency'.tr(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: 'profile.contact_name'.tr()),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration:
                    InputDecoration(labelText: 'profile.contact_phone'.tr()),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'profile.save'.tr(),
                onPressed: () {
                  ref.read(settingsProvider.notifier).setEmergencyContact(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                      );
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Journey history
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryScreen extends ConsumerWidget {
  const _HistoryScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(journeyHistoryProvider);
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(title: Text('profile.booking_history'.tr())),
      body: history.isEmpty
          ? EmptyState(
              icon: Icons.history_rounded,
              title: 'profile.no_history'.tr(),
              message: 'profile.no_history_msg'.tr(),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.pageInset),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final record = history[i];
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${record.originName} → ${record.destinationName}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${DateFormat('d MMM').format(record.departedAt)} · ${record.durationLabel} · ${record.distanceKm.toStringAsFixed(0)} km',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${record.farePaid}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings();

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  late bool _permitted;

  @override
  void initState() {
    super.initState();
    _permitted = ref.read(notificationServiceProvider).isPermitted;
  }

  Future<void> _requestPermission() async {
    final granted =
        await ref.read(notificationServiceProvider).requestPermission();
    if (mounted) setState(() => _permitted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      children: [
        if (!_permitted) ...[
          AppBanner(
            icon: Icons.notifications_active_outlined,
            tone: AppBannerTone.warning,
            title: 'profile.notif_disabled_title'.tr(),
            message: 'profile.notif_disabled_msg'.tr(),
            action: TextButton(
              onPressed: _requestPermission,
              child: Text('profile.enable'.tr()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.notifications_active_outlined,
              title: 'profile.boarding_reminders'.tr(),
              subtitle: 'profile.boarding_reminders_hint'.tr(),
              trailing: Switch(
                value: settings.arrivalAlerts,
                onChanged: notifier.setArrivalAlerts,
              ),
              onTap: settings.arrivalAlerts
                  ? null
                  : () => notifier.setArrivalAlerts(true),
            ),
            SettingsRow(
              icon: Icons.stop_circle_outlined,
              title: 'profile.arrival_alerts'.tr(),
              subtitle: settings.arrivalAlerts
                  ? 'profile.arrival_lead'
                      .tr(namedArgs: {'mins': '${settings.arrivalAlertLeadMinutes}'})
                  : 'profile.alerts_off'.tr(),
              trailing: Switch(
                value: settings.arrivalAlerts,
                onChanged: (v) {
                  notifier.setArrivalAlerts(v);
                  if (v) _showLeadPicker(context, notifier);
                },
              ),
            ),
            SettingsRow(
              icon: Icons.hotel_outlined,
              title: 'profile.halt_alerts'.tr(),
              subtitle: 'profile.halt_alerts_hint'.tr(),
              trailing: Switch(
                value: settings.haltAlerts,
                onChanged: notifier.setHaltAlerts,
              ),
            ),
            SettingsRow(
              icon: Icons.running_with_errors_outlined,
              title: 'profile.delay_alerts'.tr(),
              subtitle: 'profile.delay_alerts_hint'.tr(),
              trailing: Switch(
                value: settings.delayAlerts,
                onChanged: notifier.setDelayAlerts,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showLeadPicker(
      BuildContext context, SettingsNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: 'profile.arrival_lead_title'.tr(),
        child: Consumer(
          builder: (context, ref, _) {
            final lead = ref.watch(
                settingsProvider.select((s) => s.arrivalAlertLeadMinutes));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'profile.arrival_lead'.tr(
                      namedArgs: {'mins': '$lead'}),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  value: lead.toDouble().clamp(5, 60),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  label: '$lead min',
                  onChanged: (v) =>
                      notifier.setArrivalAlertLead(v.round()),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appearance
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final reduceMotion =
        ref.watch(settingsProvider.select((s) => s.reduceMotion));
    final largeText =
        ref.watch(settingsProvider.select((s) => s.largeText));
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsGroup(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('profile.theme'.tr(),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final m in AppThemeMode.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _ThemeModeChip(
                          mode: m,
                          selected: mode == m,
                          onTap: () => notifier.setThemeMode(m),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        SettingsRow(
          icon: Icons.motion_photos_off_outlined,
          title: 'profile.reduce_motion'.tr(),
          subtitle: 'profile.reduce_motion_hint'.tr(),
          trailing: Switch(
            value: reduceMotion,
            onChanged: notifier.setReduceMotion,
          ),
        ),
        SettingsRow(
          icon: Icons.format_size_rounded,
          title: 'profile.large_text'.tr(),
          subtitle: 'profile.large_text_hint'.tr(),
          trailing: Switch(
            value: largeText,
            onChanged: notifier.setLargeText,
          ),
        ),
      ],
    );
  }
}

class _ThemeModeChip extends StatelessWidget {
  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = switch (mode) {
      AppThemeMode.system => Icons.brightness_auto_rounded,
      AppThemeMode.light => Icons.light_mode_rounded,
      AppThemeMode.dark => Icons.dark_mode_rounded,
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? palette.brandLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
              color: selected ? palette.brand : palette.hairline),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 20,
                color: selected ? palette.brandDeep : palette.inkMuted),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mode.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? palette.brandDeep : palette.inkMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language / about / logout
// ─────────────────────────────────────────────────────────────────────────────

void _showLanguagePicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl)),
    ),
    builder: (context) {
      final currentLocale = context.locale.languageCode;
      final options = [
        ('en', 'English'),
        ('mr', 'मराठी (Marathi)'),
        ('hi', 'हिंदी (Hindi)'),
        ('kn', 'ಕನ್ನಡ (Kannada)'),
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
            for (final (code, label) in options)
              ListTile(
                title: Text(label),
                trailing: currentLocale == code
                    ? Icon(Icons.check, color: context.palette.brand)
                    : null,
                onTap: () {
                  context.setLocale(Locale(code));
                  _syncLocale(context, code);
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

/// Keep the in-app settings copy of the locale in sync with easy_localization
/// so the language survives an app restart.
void _syncLocale(BuildContext context, String code) {
  // ProfileTab is a ConsumerWidget; walk up to find the ProviderScope. The
  // settings notifier write is fire-and-forget persistence.
  final container = ProviderScope.containerOf(context);
  container.read(settingsProvider.notifier).setLocale(code);
}

void _showAbout(BuildContext context) {
  showAppSheet<void>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: BrandWordmark(),
        ),
        Text(
          'profile.about_subtitle'.tr(),
          style: Theme.of(sheetContext).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'profile.about_desc'.tr(),
          style: Theme.of(sheetContext).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ),
  );
}

void _confirmLogout(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('profile.logout'.tr()),
      content: Text('profile.logout_confirm'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('common.no'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: dialogContext.palette.danger),
          onPressed: () {
            ref.read(authRepositoryProvider).signOut();
            Navigator.of(dialogContext).pop();
            Navigator.of(context)
                .popUntil((route) => route.isFirst);
          },
          child: Text('profile.logout'.tr()),
        ),
      ],
    ),
  );
}
