/// Schedules boarding reminders for frequently-searched origin→destination pairs.
///
/// When a rider searches for the same route repeatedly (e.g. a daily commute),
/// this service learns the pattern and automatically schedules a local
/// notification before the next scheduled departure, so the rider is reminded
/// to head for the stand without having to manually set an alarm.
///
/// The implementation is intentionally conservative:
///
///  - Only pairs searched ≥ 2 times trigger an alert (the `frequentSearches`
///    threshold in `LocalStore`).
///  - Only the **next** departure for each pair is scheduled, not every daily
///    departure — the app is not a calendar and repeated daily alerts would be
///    noisy.
///  - Alert ids are deterministic (`NotificationService.idForPattern`) so a
///    re-schedule replaces the previous notification rather than stacking them.
///  - Every method is failure-tolerant: a denied permission or a crashed plugin
///    must never bring down the app.
library;

import 'package:flutter/foundation.dart';

import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/core/services/notification_service.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:busspass/data/repositories/local_store.dart';

/// Schedule one boarding reminder per frequent travel pattern.
///
/// When alerts are disabled (or there are no frequent patterns yet) every
/// previously-scheduled pattern alert is cancelled, so a rider who turns the
/// feature off is not woken the next morning by a stale reminder.
Future<void> scheduleTravelPatternAlerts({
  required JourneyPlanner planner,
  required LocalStore store,
  required NotificationService notifications,
  required bool arrivalAlertsEnabled,
  int leadMinutes = 20,
  DateTime Function()? clock,
}) async {
  final frequent = arrivalAlertsEnabled ? store.readFrequentSearches() : const [];
  if (frequent.isEmpty) {
    await _cancelAllPatterns(notifications);
    return;
  }

  final now = (clock ?? DateTime.now)();
  for (final search in frequent) {
    await _scheduleForPattern(
      search: search,
      planner: planner,
      notifications: notifications,
      now: now,
      leadMinutes: leadMinutes,
    );
  }
}


/// Cancel every previously-scheduled pattern alert.
///
/// The set of possible patterns is bounded by the recent-search cap (12), so we
/// can enumerate the range of stable ids without needing to query the OS.
Future<void> _cancelAllPatterns(NotificationService notifications) async {
  for (var i = 0; i < NotificationService.patternAlertSlots; i++) {
    await notifications.cancelId(NotificationService.patternAlertBaseId + i);
  }
}

Future<void> _scheduleForPattern({
  required RecentSearch search,
  required JourneyPlanner planner,
  required NotificationService notifications,
  required DateTime now,
  required int leadMinutes,
}) async {
  final direct = _nextDirectDeparture(
    planner: planner,
    originId: search.originStopId,
    destinationId: search.destinationStopId,
    after: now,
  );

  if (direct == null) {
    // No service covers this pair today, or every departure has passed. Cancel
    // any stale alert scheduled on a previous run.
    await notifications.cancelPatternAlert(search.key);
    return;
  }

  final boardTime = direct.boardTime;
  final alertTime = boardTime.subtract(Duration(minutes: leadMinutes));
  if (!alertTime.isAfter(now)) {
    await notifications.cancelPatternAlert(search.key);
    return;
  }

  final clock =
      '${boardTime.hour.toString().padLeft(2, '0')}:${boardTime.minute.toString().padLeft(2, '0')}';

  await notifications.scheduleAt(
    id: NotificationService.idForPattern(search.key),
    when: alertTime,
    title: 'Bus to ${direct.destName} at $clock',
    body: 'Head to ${direct.originName} — departure in $leadMinutes minutes.',
    channel: AlertChannel.journey,
    payload: 'pattern:${search.key}',
  );

  debugPrint(
    'TravelPatternAlert: "$clock" ${direct.originName} → ${direct.destName} '
    '(alert ${alertTime.hour}:${alertTime.minute.toString().padLeft(2, '0')})',
  );
}

/// Compute the next direct departure from [originId] to [destinationId].
///
/// Returns the board time (when the bus reaches the origin stop) and the
/// destination name, or null when no service calls at both stops in the
/// expected order. Services are considered regardless of direction; only a
/// service that reaches the destination after the origin qualifies.
_DirectDeparture? _nextDirectDeparture({
  required JourneyPlanner planner,
  required String originId,
  required String destinationId,
  required DateTime after,
}) {
  final graph = planner.graph;
  final network = graph.network;
  _DirectDeparture? best;

  for (final call in graph.callsAt(originId)) {
    final route = call.route;
    final service = call.service;

    final originSeq = call.seq;
    final destSeq = route.stopRefById(destinationId)?.seq;
    if (destSeq == null || destSeq == originSeq) continue;

    final offsets = planner.boardOffsets(service, route);
    final boardOffset = offsets[originSeq] ?? 0;

    final status = Schedule.statusFor(service.departures, after);
    final next = status.next;
    if (next == null) continue;

    final boardTime = Schedule.resolve(
      Schedule.addMinutes(next.minuteOfDay, boardOffset),
      after,
    );

    if (best == null || boardTime.minutesUntil < best.minutesUntil) {
      final boardRef = route.stopRefBySeq(originSeq);
      final destRef = route.stopRefBySeq(destSeq);
      final destStop = network.stopById(destinationId);
      best = _DirectDeparture(
        boardTime: boardTime.at,
        minutesUntil: boardTime.minutesUntil,
        originName: boardRef?.city ??
            network.stopById(originId)?.city ??
            originId,
        destName: destStop?.city ?? destRef?.city ?? destinationId,
      );
    }
  }

  return best;
}

class _DirectDeparture {
  final DateTime boardTime;
  final int minutesUntil;
  final String originName;
  final String destName;

  const _DirectDeparture({
    required this.boardTime,
    required this.minutesUntil,
    required this.originName,
    required this.destName,
  });
}
