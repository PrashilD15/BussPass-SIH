/// Passes — the rider's real held tickets, grouped by state.
///
/// The old version showed a decorative "DEMO" pass card and a no-op button.
/// Everything here is read from `ticketsProvider`: live entitlements, their
/// countdown, and past journeys from the local store.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/features/journey/presentation/journey_search_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class PassesTab extends ConsumerWidget {
  const PassesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(ticketBucketsProvider);
    final now = ref.watch(clockProvider);

    final live = buckets.live;
    final past = buckets.past;

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(
        title: Text('passes.title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageInset, AppSpacing.md, AppSpacing.pageInset, 120),
        children: [
          if (live.isEmpty && past.isEmpty) ...[
            const SizedBox(height: AppSpacing.xxxl),
            EmptyState(
              icon: Icons.confirmation_num_outlined,
              title: 'passes.empty_title'.tr(),
              message: 'passes.empty_msg'.tr(),
              actionLabel: 'passes.browse_routes'.tr(),
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const JourneySearchScreen()),
              ),
            ),
          ],

          if (live.isNotEmpty) ...[
            SectionHeader(
                title: 'passes.current'.tr(),
                subtitle: '${live.length} live'),
            const SizedBox(height: AppSpacing.md),
            for (final ticket in live)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _TicketCard(ticket: ticket, now: now),
              ),
          ],

          if (past.isNotEmpty) ...[
            SizedBox(height: live.isEmpty ? 0 : AppSpacing.xxl),
            SectionHeader(title: 'passes.history'.tr()),
            const SizedBox(height: AppSpacing.md),
            for (final ticket in past)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PastTicketRow(ticket: ticket),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active / upcoming ticket
// ─────────────────────────────────────────────────────────────────────────────

class _TicketCard extends ConsumerWidget {
  final Ticket ticket;
  final DateTime now;
  const _TicketCard({required this.ticket, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final status = ticket.statusAt(now);
    final isPass = ticket.isPass;
    final minutesTo = ticket.minutesUntilDeparture(now);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette.gradientBrand,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: AppShadow.glowBrand(palette.brand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
            child: Row(
              children: [
                TagChip(
                  label: isPass
                      ? 'passes.pass'.tr()
                      : status == TicketStatus.active
                          ? 'passes.on_board'.tr()
                          : 'passes.upcoming'.tr(),
                  foreground: palette.onBrand,
                  background: palette.onBrand.withValues(alpha: 0.18),
                  dense: true,
                ),
                const Spacer(),
                if (!isPass && status == TicketStatus.upcoming)
                  Text(
                    minutesTo > 0
                        ? 'passes.leaves_in'
                            .tr(namedArgs: {'minutes': '$minutesTo'})
                        : 'passes.boarding'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.onBrand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.originName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: palette.onBrand,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward_rounded,
                          size: 14,
                          color:
                              palette.onBrand.withValues(alpha: 0.6)),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        height: 28,
                        width: 1.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              palette.onBrand.withValues(alpha: 0.0),
                              palette.onBrand.withValues(alpha: 0.3),
                              palette.onBrand.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  ticket.destinationName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: palette.onBrand,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.lg),
                _TicketDetailRow(
                    icon: Icons.category_outlined,
                    text: ticket.serviceClassKey),
                const SizedBox(height: AppSpacing.xs),
                _TicketDetailRow(
                  icon: Icons.schedule_rounded,
                  text:
                      '${DateFormat.jm().format(ticket.departsAt)} → ${DateFormat.jm().format(ticket.arrivesAt)}',
                ),
                if (isPass) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _TicketDetailRow(
                    icon: Icons.event_repeat_rounded,
                    text: 'passes.valid_till'
                        .tr(namedArgs: {'date': _fmtDate(ticket.validUntil)}),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        '₹${ticket.amountPaid}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: palette.onBrand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (ticket.concession > 0)
                      Text(
                        'passes.saved'
                            .tr(namedArgs: {'amount': '₹${ticket.concession}'}),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: palette.onBrand.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Ref ${ticket.reference} · ${ticket.paymentMethod.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.onBrand.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'passes.cancel_ticket'.tr(),
                  outlined: false,
                  backgroundColor: palette.onBrand,
                  foregroundColor: palette.brandDeep,
                  onPressed: () =>
                      _confirmCancel(context, ref, ticket),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('d MMM y').format(d);

  void _confirmCancel(BuildContext context, WidgetRef ref, Ticket ticket) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('passes.cancel_title'.tr()),
        content: Text('passes.cancel_msg'
            .tr(namedArgs: {'route': ticket.routeLabel})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.no'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: dialogContext.palette.danger),
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(ticketsProvider.notifier).cancel(ticket.id);
            },
            child: Text('passes.cancel_confirm'.tr()),
          ),
        ],
      ),
    );
  }
}

class _TicketDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TicketDetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.onBrand.withValues(alpha: 0.65)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.onBrand,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Past ticket row
// ─────────────────────────────────────────────────────────────────────────────

class _PastTicketRow extends ConsumerWidget {
  final Ticket ticket;
  const _PastTicketRow({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final status = ticket.statusAt(ref.watch(clockProvider));

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              status == TicketStatus.cancelled
                  ? Icons.remove_circle_outline_rounded
                  : status == TicketStatus.expired
                      ? Icons.hourglass_empty_rounded
                      : Icons.check_circle_outline_rounded,
              size: 19,
              color: status == TicketStatus.completed
                  ? palette.success
                  : palette.inkMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.routeLabel,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${DateFormat('d MMM').format(ticket.departsAt)} · ${status.label}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '₹${ticket.amountPaid}',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}
