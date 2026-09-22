/// Data-honesty chips: [OccupancyPill], [DelayChip], [ProvenanceChip].
///
/// These surface fields the backend has always carried — crowd level, delay
/// against schedule, and where a value came from — but the old UI never showed.
library;

import 'package:flutter/material.dart';

import 'package:busspass/core/math/occupancy_engine.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/providers/app_providers.dart' show LiveSource;
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// Crowd level as a tinted pill. The level picks fg and bg together via
/// [AppPalette.forCrowdLevel] / [AppPalette.crowdTint] so the pair never drifts.
class OccupancyPill extends StatelessWidget {
  final CrowdLevel level;

  /// Extra context, e.g. "· 12 seats free".
  final String? detail;

  const OccupancyPill({super.key, required this.level, this.detail});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = palette.forCrowdLevel(level.index);
    final bg = palette.crowdTint(level.index);
    final icon = switch (level) {
      CrowdLevel.empty => Icons.event_seat_rounded,
      CrowdLevel.light => Icons.event_available_rounded,
      CrowdLevel.moderate => Icons.people_alt_rounded,
      CrowdLevel.full => Icons.group_rounded,
      CrowdLevel.crushed => Icons.groups_rounded,
    };

    return _Pill(
      icon: icon,
      label: detail == null ? level.label : '${level.label} · $detail',
      foreground: fg,
      background: bg,
    );
  }
}

/// On-time / late against the scheduled departure.
class DelayChip extends StatelessWidget {
  final LiveBus bus;
  final DateTime now;

  const DelayChip({super.key, required this.bus, required this.now});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lateMin = now.difference(bus.scheduledDeparture).inMinutes;

    if (lateMin < -1) {
      return _Pill(
        icon: Icons.schedule_rounded,
        label: 'Departs in ${-lateMin} min',
        foreground: palette.info,
        background: palette.infoLight,
      );
    }
    if (lateMin <= 5) {
      return _Pill(
        icon: Icons.check_circle_rounded,
        label: 'On time',
        foreground: palette.success,
        background: palette.successLight,
      );
    }
    final tone = lateMin <= 20 ? palette.warning : palette.danger;
    final bg = lateMin <= 20 ? palette.warningLight : palette.dangerLight;
    return _Pill(
      icon: Icons.running_with_errors_rounded,
      label: '+$lateMin min late',
      foreground: tone,
      background: bg,
    );
  }
}

/// Where a value came from — live GPS vs simulator, published vs estimated
/// times. Shown rather than hidden so the rider can weigh what they're told.
class ProvenanceChip extends StatelessWidget {
  final LiveSource source;
  final ScheduleConfidence? scheduleConfidence;

  const ProvenanceChip({
    super.key,
    required this.source,
    this.scheduleConfidence,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (scheduleConfidence != null &&
        !scheduleConfidence!.isPublished) {
      return _Pill(
        icon: Icons.timeline_rounded,
        label: scheduleConfidence!.label,
        foreground: palette.warning,
        background: palette.warningLight,
        tooltip: scheduleConfidence!.explanation,
      );
    }

    return switch (source) {
      LiveSource.realtimeDatabase => _Pill(
          icon: Icons.satellite_alt_rounded,
          label: 'Live GPS',
          foreground: palette.success,
          background: palette.successLight,
        ),
      LiveSource.simulator => _Pill(
          icon: Icons.science_rounded,
          label: 'Simulated',
          foreground: palette.info,
          background: palette.infoLight,
        ),
      LiveSource.none => _Pill(
          icon: Icons.cloud_off_rounded,
          label: 'Offline times',
          foreground: palette.inkMuted,
          background: palette.surfaceAlt,
        ),
    };
  }
}

/// A leg's schedule-provenance badge. Published boards need no warning; only
/// estimated times are surfaced, so a "Published" chip never becomes noise.
class ScheduleConfidenceBadge extends StatelessWidget {
  final ScheduleConfidence confidence;
  const ScheduleConfidenceBadge({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    if (confidence.isPublished) return const SizedBox.shrink();
    final palette = context.palette;
    return _Pill(
      icon: Icons.timeline_rounded,
      label: confidence.label,
      foreground: palette.warning,
      background: palette.warningLight,
      tooltip: confidence.explanation,
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final String? tooltip;

  const _Pill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs + 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppSpacing.brPill,
        border: Border.all(color: foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );

    return Tooltip(message: tooltip ?? label, child: pill);
  }
}
