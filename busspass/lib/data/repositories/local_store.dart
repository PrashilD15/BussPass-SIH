/// Local persistence.
///
/// Backed by `shared_preferences`, which was already a declared dependency but
/// had never been imported — every "recent search" and "saved place" in the old
/// UI was a hardcoded literal pretending to be user data.
///
/// Everything here is JSON-serialised under a versioned key prefix so a future
/// schema change can migrate rather than silently misread. Reads are defensive:
/// corrupt stored data is discarded and logged, never thrown at the UI, because
/// a bad cache entry must not brick the app.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/data/models/ticket.dart';

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  /// Bumping this prefix invalidates all stored data at once.
  static const String _v = 'bp.v1';

  static const String _kTickets = '$_v.tickets';
  static const String _kSavedPlaces = '$_v.savedPlaces';
  static const String _kRecentSearches = '$_v.recentSearches';
  static const String _kJourneyHistory = '$_v.journeyHistory';
  static const String _kFeedback = '$_v.feedback';
  static const String _kSettings = '$_v.settings';
  static const String _kOnboarded = '$_v.onboarded';
  static const String _kActiveTicket = '$_v.activeTicket';

  /// Cap on retained recent searches.
  static const int _recentSearchLimit = 12;

  /// Cap on retained journey history.
  static const int _historyLimit = 100;

  // ── Generic list helpers ───────────────────────────────────────────────

  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) parse) {
    final raw = _prefs.getStringList(key);
    if (raw == null) return [];

    final out = <T>[];
    var corrupt = 0;
    for (final entry in raw) {
      try {
        out.add(parse(jsonDecode(entry) as Map<String, dynamic>));
      } catch (_) {
        corrupt++;
      }
    }
    if (corrupt > 0) {
      debugPrint('LocalStore: discarded $corrupt corrupt entries under $key');
    }
    return out;
  }

  Future<void> _writeList<T>(
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) encode,
  ) async {
    await _prefs.setStringList(
      key,
      items.map((item) => jsonEncode(encode(item))).toList(),
    );
  }

  // ── Tickets and passes ────────────────────────────────────────────────

  List<Ticket> readTickets() => _readList(_kTickets, Ticket.fromJson);

  Future<void> writeTickets(List<Ticket> tickets) =>
      _writeList(_kTickets, tickets, (t) => t.toJson());

  Future<void> addTicket(Ticket ticket) async {
    final tickets = readTickets()
      ..removeWhere((t) => t.id == ticket.id)
      ..add(ticket);
    tickets.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    await writeTickets(tickets);
  }

  Future<void> updateTicket(Ticket ticket) => addTicket(ticket);

  Future<void> removeTicket(String ticketId) async {
    final tickets = readTickets()..removeWhere((t) => t.id == ticketId);
    await writeTickets(tickets);
  }

  /// The ticket the rider is currently travelling on, if any.
  String? readActiveTicketId() => _prefs.getString(_kActiveTicket);

  Future<void> writeActiveTicketId(String? ticketId) async {
    if (ticketId == null) {
      await _prefs.remove(_kActiveTicket);
    } else {
      await _prefs.setString(_kActiveTicket, ticketId);
    }
  }

  // ── Saved places ──────────────────────────────────────────────────────

  List<SavedPlace> readSavedPlaces() =>
      _readList(_kSavedPlaces, SavedPlace.fromJson);

  Future<void> writeSavedPlaces(List<SavedPlace> places) =>
      _writeList(_kSavedPlaces, places, (p) => p.toJson());

  Future<void> addSavedPlace(SavedPlace place) async {
    final places = readSavedPlaces();
    // Home and Work are singletons — saving a new Home replaces the old one
    // rather than accumulating duplicates.
    if (place.kind != SavedPlaceKind.other) {
      places.removeWhere((p) => p.kind == place.kind);
    }
    places
      ..removeWhere((p) => p.stopId == place.stopId)
      ..add(place);
    await writeSavedPlaces(places);
  }

  Future<void> removeSavedPlace(String id) async {
    final places = readSavedPlaces()..removeWhere((p) => p.id == id);
    await writeSavedPlaces(places);
  }

  // ── Recent searches ───────────────────────────────────────────────────

  /// Recent searches, most recently used first.
  List<RecentSearch> readRecentSearches() {
    final searches = _readList(_kRecentSearches, RecentSearch.fromJson)
      ..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return searches;
  }

  /// Record a search, merging with an existing entry for the same pair.
  ///
  /// Merging rather than appending keeps the list useful: a rider who commutes
  /// the same route daily should see it once with a high count, not twelve times.
  Future<void> recordSearch(RecentSearch search) async {
    final searches = readRecentSearches();
    final existingIndex = searches.indexWhere((s) => s.key == search.key);

    if (existingIndex >= 0) {
      final merged = searches[existingIndex].bumped();
      searches[existingIndex] = merged;
    } else {
      searches.insert(0, search);
    }

    searches.sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    final trimmed = searches.take(_recentSearchLimit).toList();
    await _writeList(_kRecentSearches, trimmed, (s) => s.toJson());
  }

  /// Frequently searched pairs, for home-screen suggestions.
  List<RecentSearch> readFrequentSearches({int limit = 4}) {
    final searches = readRecentSearches()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.searchedAt.compareTo(a.searchedAt);
      });
    return searches.where((s) => s.count > 1).take(limit).toList();
  }

  Future<void> clearRecentSearches() => _prefs.remove(_kRecentSearches);

  // ── Journey history ───────────────────────────────────────────────────

  List<JourneyRecord> readJourneyHistory() {
    final history = _readList(_kJourneyHistory, JourneyRecord.fromJson)
      ..sort((a, b) => b.departedAt.compareTo(a.departedAt));
    return history;
  }

  Future<void> addJourneyRecord(JourneyRecord record) async {
    final history = readJourneyHistory()
      ..removeWhere((r) => r.id == record.id)
      ..insert(0, record);
    final trimmed = history.take(_historyLimit).toList();
    await _writeList(_kJourneyHistory, trimmed, (r) => r.toJson());
  }

  /// Lifetime travel totals, for the profile screen.
  ({int journeys, double distanceKm, int fareSpent, int minutesTravelled})
      travelTotals() {
    final history = readJourneyHistory();
    return (
      journeys: history.length,
      distanceKm: history.fold<double>(0, (sum, r) => sum + r.distanceKm),
      fareSpent: history.fold<int>(0, (sum, r) => sum + r.farePaid),
      minutesTravelled:
          history.fold<int>(0, (sum, r) => sum + r.durationMinutes),
    );
  }

  // ── Feedback ──────────────────────────────────────────────────────────

  List<JourneyFeedback> readFeedback() =>
      _readList(_kFeedback, JourneyFeedback.fromJson);

  Future<void> addFeedback(JourneyFeedback feedback) async {
    final all = readFeedback()
      ..removeWhere((f) => f.ticketId == feedback.ticketId)
      ..add(feedback);
    await _writeList(_kFeedback, all, (f) => f.toJson());
  }

  /// Whether the rider has already rated a journey, so the prompt is not
  /// repeated.
  bool hasFeedbackFor(String ticketId) =>
      readFeedback().any((f) => f.ticketId == ticketId);

  // ── Settings ──────────────────────────────────────────────────────────

  AppSettings readSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      debugPrint('LocalStore: settings corrupt, reverting to defaults');
      return AppSettings.defaults;
    }
  }

  Future<void> writeSettings(AppSettings settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));

  // ── Onboarding ────────────────────────────────────────────────────────

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  /// Wipe everything. Used by "clear local data" in settings, and by sign-out.
  Future<void> clearAll() async {
    for (final key in [
      _kTickets,
      _kSavedPlaces,
      _kRecentSearches,
      _kJourneyHistory,
      _kFeedback,
      _kActiveTicket,
    ]) {
      await _prefs.remove(key);
    }
  }
}

/// Rider preferences.
class AppSettings {
  /// Locale code: `en`, `hi`, `mr`, `kn`.
  final String localeCode;

  /// Theme preference.
  final AppThemeMode themeMode;

  /// Default concession category, so a senior citizen is not re-selecting it on
  /// every booking.
  final RiderCategory riderCategory;

  /// Ranking preference for journey results.
  final String journeyPreference;

  /// Alert me before my stop.
  final bool arrivalAlerts;

  /// Minutes before arrival to alert.
  final int arrivalAlertLeadMinutes;

  /// Alert me when a rest halt is ending.
  final bool haltAlerts;

  /// Alert me about delays on a tracked service.
  final bool delayAlerts;

  /// Reduce animation, for motion sensitivity.
  final bool reduceMotion;

  /// Larger text, independent of the OS setting.
  final bool largeText;

  /// Emergency contact for the SOS action.
  final String emergencyContactName;
  final String emergencyContactPhone;

  const AppSettings({
    required this.localeCode,
    required this.themeMode,
    required this.riderCategory,
    required this.journeyPreference,
    required this.arrivalAlerts,
    required this.arrivalAlertLeadMinutes,
    required this.haltAlerts,
    required this.delayAlerts,
    required this.reduceMotion,
    required this.largeText,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  static const AppSettings defaults = AppSettings(
    localeCode: 'en',
    themeMode: AppThemeMode.system,
    riderCategory: RiderCategory.adult,
    journeyPreference: 'fastest',
    arrivalAlerts: true,
    arrivalAlertLeadMinutes: 5,
    haltAlerts: true,
    delayAlerts: true,
    reduceMotion: false,
    largeText: false,
    emergencyContactName: '',
    emergencyContactPhone: '',
  );

  bool get hasEmergencyContact => emergencyContactPhone.trim().isNotEmpty;

  AppSettings copyWith({
    String? localeCode,
    AppThemeMode? themeMode,
    RiderCategory? riderCategory,
    String? journeyPreference,
    bool? arrivalAlerts,
    int? arrivalAlertLeadMinutes,
    bool? haltAlerts,
    bool? delayAlerts,
    bool? reduceMotion,
    bool? largeText,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) =>
      AppSettings(
        localeCode: localeCode ?? this.localeCode,
        themeMode: themeMode ?? this.themeMode,
        riderCategory: riderCategory ?? this.riderCategory,
        journeyPreference: journeyPreference ?? this.journeyPreference,
        arrivalAlerts: arrivalAlerts ?? this.arrivalAlerts,
        arrivalAlertLeadMinutes:
            arrivalAlertLeadMinutes ?? this.arrivalAlertLeadMinutes,
        haltAlerts: haltAlerts ?? this.haltAlerts,
        delayAlerts: delayAlerts ?? this.delayAlerts,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        largeText: largeText ?? this.largeText,
        emergencyContactName:
            emergencyContactName ?? this.emergencyContactName,
        emergencyContactPhone:
            emergencyContactPhone ?? this.emergencyContactPhone,
      );

  Map<String, dynamic> toJson() => {
        'locale': localeCode,
        'theme_mode': themeMode.name,
        'rider_category': riderCategory.name,
        'journey_preference': journeyPreference,
        'arrival_alerts': arrivalAlerts,
        'arrival_alert_lead': arrivalAlertLeadMinutes,
        'halt_alerts': haltAlerts,
        'delay_alerts': delayAlerts,
        'reduce_motion': reduceMotion,
        'large_text': largeText,
        'emergency_contact_name': emergencyContactName,
        'emergency_contact_phone': emergencyContactPhone,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        localeCode: json['locale'] as String? ?? 'en',
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == json['theme_mode'],
          orElse: () => AppThemeMode.system,
        ),
        riderCategory: RiderCategory.values.firstWhere(
          (c) => c.name == json['rider_category'],
          orElse: () => RiderCategory.adult,
        ),
        journeyPreference: json['journey_preference'] as String? ?? 'fastest',
        arrivalAlerts: json['arrival_alerts'] as bool? ?? true,
        arrivalAlertLeadMinutes:
            (json['arrival_alert_lead'] as num?)?.toInt() ?? 5,
        haltAlerts: json['halt_alerts'] as bool? ?? true,
        delayAlerts: json['delay_alerts'] as bool? ?? true,
        reduceMotion: json['reduce_motion'] as bool? ?? false,
        largeText: json['large_text'] as bool? ?? false,
        emergencyContactName:
            json['emergency_contact_name'] as String? ?? '',
        emergencyContactPhone:
            json['emergency_contact_phone'] as String? ?? '',
      );
}

/// Theme preference. Mirrors Flutter's `ThemeMode` but is serialisable and
/// carries a display label.
enum AppThemeMode {
  system('Match device'),
  light('Light'),
  dark('Dark');

  const AppThemeMode(this.label);
  final String label;
}
