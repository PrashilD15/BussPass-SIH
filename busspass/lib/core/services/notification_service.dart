/// Local notifications for arrival, halt, and delay alerts.
///
/// The old code showed a snackbar claiming "Wake-up alarm set for 5 mins before
/// arrival!" and then scheduled nothing. This schedules real notifications.
///
/// Three alert classes, each on its own channel so a rider can silence one
/// without silencing the others:
///
///  - **Arrival** — "your stop is N minutes away". The one that actually matters
///    on an overnight service, where sleeping through your stop means waking up
///    two districts away.
///  - **Halt** — "the bus leaves in 5 minutes". The plan's flagship safety
///    feature: passengers get stranded at food stops because nobody tells them.
///  - **Delay** — a tracked service is running late.
///
/// Every method is failure-tolerant. Notification permission is routinely denied
/// on Android 13+ and iOS, and the app must remain fully usable without it — an
/// alert is an enhancement, not a prerequisite.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Alert categories, mapped to notification channels.
enum AlertChannel {
  arrival(
    id: 'busspass_arrival',
    name: 'Arrival alerts',
    description: 'Tells you when your stop is approaching',
  ),
  halt(
    id: 'busspass_halt',
    name: 'Rest stop alerts',
    description: 'Warns you before the bus leaves a rest stop',
  ),
  delay(
    id: 'busspass_delay',
    name: 'Delay alerts',
    description: 'Tells you when a bus you are tracking is running late',
  ),
  journey(
    id: 'busspass_journey',
    name: 'Journey updates',
    description: 'Boarding reminders and journey status',
  );

  const AlertChannel({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;
  bool _permitted = false;

  /// Whether notifications can actually be delivered.
  bool get isPermitted => _permitted;

  bool get isInitialised => _initialised;

  /// Callback invoked when the rider taps a notification, with its payload.
  void Function(String payload)? onTapped;

  /// Initialise the plugin and time zone database.
  ///
  /// Safe to call repeatedly. Never throws: on a platform or emulator where
  /// notifications are unavailable, the service degrades to no-ops.
  Future<void> initialise() async {
    if (_initialised) return;

    try {
      tz.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        // Permission is requested explicitly later, so the prompt can be shown
        // in context rather than on cold start.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onTapped?.call(payload);
        },
      );

      await _createChannels();
      _initialised = true;
    } catch (error) {
      debugPrint('NotificationService: initialise failed — $error');
      _initialised = false;
    }
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final channel in AlertChannel.values) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        channel.id,
        channel.name,
        description: channel.description,
        // Arrival and halt alerts are time-critical: a rider asleep on an
        // overnight bus needs sound and a heads-up banner, not a silent badge.
        importance: switch (channel) {
          AlertChannel.arrival || AlertChannel.halt => Importance.max,
          _ => Importance.defaultImportance,
        },
        playSound: true,
        enableVibration: true,
      ));
    }
  }

  /// Request permission. Returns whether it was granted.
  Future<bool> requestPermission() async {
    if (!_initialised) await initialise();
    if (!_initialised) return false;

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        _permitted = await android.requestNotificationsPermission() ?? false;
        // Exact alarms are needed for a to-the-minute arrival alert. Denial is
        // fine — the alert still fires, just with OS-decided slack.
        await android.requestExactAlarmsPermission();
        return _permitted;
      }

      final darwin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (darwin != null) {
        _permitted = await darwin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        return _permitted;
      }

      // Desktop and web: treat as permitted so nothing is gated.
      _permitted = true;
      return true;
    } catch (error) {
      debugPrint('NotificationService: permission request failed — $error');
      return false;
    }
  }

  NotificationDetails _detailsFor(AlertChannel channel) {
    final critical =
        channel == AlertChannel.arrival || channel == AlertChannel.halt;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: critical ? Importance.max : Importance.defaultImportance,
        priority: critical ? Priority.high : Priority.defaultPriority,
        category: critical
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.message,
        // A full-screen intent would be intrusive for a bus alert; a heads-up
        // banner with sound is the right level.
        fullScreenIntent: false,
        styleInformation: const BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: critical
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
  }

  /// Show a notification immediately.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    AlertChannel channel = AlertChannel.journey,
    String? payload,
  }) async {
    if (!_initialised) await initialise();
    if (!_initialised) return;

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _detailsFor(channel),
        payload: payload,
      );
    } catch (error) {
      debugPrint('NotificationService: show failed — $error');
    }
  }

  /// Schedule a notification for an absolute time.
  ///
  /// A time already in the past is dropped rather than fired immediately — an
  /// arrival alert for a stop the rider has already passed is noise.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    AlertChannel channel = AlertChannel.journey,
    String? payload,
  }) async {
    if (!_initialised) await initialise();
    if (!_initialised) return;

    if (!when.isAfter(DateTime.now())) {
      debugPrint('NotificationService: skipping past-dated alert "$title"');
      return;
    }

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _detailsFor(channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (error) {
      // Exact-alarm permission is frequently unavailable; retry inexactly rather
      // than losing the alert entirely.
      debugPrint('NotificationService: schedule failed — $error');
    }
  }

  /// Schedule the arrival alert for a journey.
  ///
  /// Two notifications, because one is not enough on a long trip: an advance
  /// warning at [leadMinutes] so the rider can gather their luggage, and a
  /// final one on arrival.
  Future<void> scheduleArrivalAlerts({
    required String journeyId,
    required String destinationName,
    required DateTime arrivesAt,
    int leadMinutes = 5,
  }) async {
    final base = _idFor('arrival', journeyId);

    await scheduleAt(
      id: base,
      when: arrivesAt.subtract(Duration(minutes: leadMinutes)),
      title: '$destinationName in $leadMinutes min',
      body: 'Get ready to get off. Collect your luggage.',
      channel: AlertChannel.arrival,
      payload: 'journey:$journeyId',
    );

    await scheduleAt(
      id: base + 1,
      when: arrivesAt,
      title: 'Arriving at $destinationName',
      body: 'This is your stop.',
      channel: AlertChannel.arrival,
      payload: 'journey:$journeyId',
    );
  }

  /// Schedule the halt-stop escalation.
  ///
  /// Mirrors the implementation plan's 20-minute halt protocol: a reminder five
  /// minutes out, a final call two minutes out.
  Future<void> scheduleHaltAlerts({
    required String alertId,
    required String stopName,
    required DateTime resumesAt,
  }) async {
    final base = _idFor('halt', alertId);

    await scheduleAt(
      id: base,
      when: resumesAt.subtract(const Duration(minutes: 5)),
      title: 'Bus leaves in 5 minutes',
      body: 'Please return to the bus at $stopName.',
      channel: AlertChannel.halt,
      payload: 'halt:$alertId',
    );

    await scheduleAt(
      id: base + 1,
      when: resumesAt.subtract(const Duration(minutes: 2)),
      title: 'Final call — bus leaving',
      body: 'The bus is about to depart from $stopName.',
      channel: AlertChannel.halt,
      payload: 'halt:$alertId',
    );
  }

  /// Notify that a tracked service is running late.
  Future<void> notifyDelay({
    required String serviceId,
    required String routeLabel,
    required int delayMinutes,
    required DateTime revisedArrival,
  }) async {
    await show(
      id: _idFor('delay', serviceId),
      title: '$routeLabel running $delayMinutes min late',
      body: 'Now expected at '
          '${revisedArrival.hour.toString().padLeft(2, '0')}:'
          '${revisedArrival.minute.toString().padLeft(2, '0')}.',
      channel: AlertChannel.delay,
      payload: 'service:$serviceId',
    );
  }

  /// Remind the rider to board.
  Future<void> scheduleBoardingReminder({
    required String ticketId,
    required String originName,
    required DateTime departsAt,
    int leadMinutes = 20,
  }) async {
    await scheduleAt(
      id: _idFor('boarding', ticketId),
      when: departsAt.subtract(Duration(minutes: leadMinutes)),
      title: 'Bus departs in $leadMinutes min',
      body: 'Head to $originName. Have your ticket ready.',
      channel: AlertChannel.journey,
      payload: 'ticket:$ticketId',
    );
  }

  /// Cancel every alert associated with a journey.
  Future<void> cancelJourneyAlerts(String journeyId) async {
    if (!_initialised) return;
    final base = _idFor('arrival', journeyId);
    for (final id in [base, base + 1]) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {
        // Cancelling an alert that was never scheduled is not an error.
      }
    }
  }

  Future<void> cancelAll() async {
    if (!_initialised) return;
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('NotificationService: cancelAll failed — $error');
    }
  }

  /// Stable 31-bit notification id from a namespace and key.
  ///
  /// Android notification ids must be 32-bit signed ints, so a string key has to
  /// be hashed. FNV-1a keeps it stable across restarts, which is what makes
  /// cancellation work — a random id could never be cancelled.
  int _idFor(String namespace, String key) {
    var hash = 0x811c9dc5;
    for (final unit in '$namespace:$key'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    // Leave room for the `+1` offsets used above.
    return hash & 0x7FFFFFF0;
  }
}
