/// Tickets, passes, and the journeys they belong to.
///
/// MSRTC tickets are issued by a conductor at a POS, not bought in-app. The app
/// therefore models two distinct things that the old `PassesTab` conflated:
///
///  - a **ticket**, a single point-to-point journey with a QR that a conductor
///    can validate, and
///  - a **pass**, a time-bounded travel entitlement (student, senior, monthly)
///    that is presented rather than punched.
///
/// Both are persisted locally so a rider can show a ticket in a tunnel with no
/// signal — which is precisely when they will be asked for it.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/schedule.dart';

/// Lifecycle of a ticket.
enum TicketStatus {
  /// Paid for, journey not yet started.
  upcoming('Upcoming'),

  /// Rider is on board.
  active('On board'),

  /// Journey finished.
  completed('Completed'),

  /// Refunded or voided before travel.
  cancelled('Cancelled'),

  /// The service departed without the rider boarding.
  expired('Expired');

  const TicketStatus(this.label);
  final String label;

  bool get isLive => this == upcoming || this == active;
}

/// What kind of entitlement this is.
enum TicketKind {
  /// Single point-to-point journey.
  single('Single journey'),

  /// Out and back on the same day.
  returnTrip('Return journey'),

  /// Unlimited travel within a validity window.
  pass('Travel pass');

  const TicketKind(this.label);
  final String label;
}

/// Validity period for a pass.
enum PassPeriod {
  daily('Daily', 1),
  weekly('Weekly', 7),
  monthly('Monthly', 30),
  quarterly('Quarterly', 90);

  const PassPeriod(this.label, this.days);
  final String label;
  final int days;
}

/// How the fare was settled.
enum PaymentMethod {
  upi('UPI'),
  card('Card'),
  wallet('BussPass Wallet'),
  cashOnBoard('Cash to conductor');

  const PaymentMethod(this.label);
  final String label;
}

/// A ticket or pass held by the rider.
class Ticket {
  /// Stable identifier, also the QR payload subject.
  final String id;

  /// Human-readable reference a conductor can read aloud.
  final String reference;

  final TicketKind kind;
  final TicketStatus status;

  // ── Journey ────────────────────────────────────────────────────────────
  final String originStopId;
  final String originName;
  final String destinationStopId;
  final String destinationName;

  /// Route the ticket is valid on. Empty for an any-route pass.
  final String routeId;

  /// Service class the fare was computed at.
  final String serviceClassKey;

  /// Scheduled departure.
  final DateTime departsAt;

  /// Scheduled arrival.
  final DateTime arrivesAt;

  /// Chargeable distance, kilometres.
  final double distanceKm;

  // ── Commercial ─────────────────────────────────────────────────────────
  final RiderCategory riderCategory;

  /// Amount actually paid, rupees.
  final int amountPaid;

  /// Adult fare before concession, for the receipt.
  final int baseFare;

  final int passengers;
  final PaymentMethod paymentMethod;

  /// Seat numbers, when the service is reserved.
  final List<String> seats;

  // ── Pass-only ──────────────────────────────────────────────────────────
  final PassPeriod? passPeriod;
  final DateTime? validFrom;
  final DateTime? validUntil;

  // ── Audit ──────────────────────────────────────────────────────────────
  final DateTime issuedAt;

  /// When a conductor scanned the QR. Null until validated.
  final DateTime? validatedAt;

  /// Depot or conductor id that validated it.
  final String? validatedBy;

  const Ticket({
    required this.id,
    required this.reference,
    required this.kind,
    required this.status,
    required this.originStopId,
    required this.originName,
    required this.destinationStopId,
    required this.destinationName,
    required this.routeId,
    required this.serviceClassKey,
    required this.departsAt,
    required this.arrivesAt,
    required this.distanceKm,
    required this.riderCategory,
    required this.amountPaid,
    required this.baseFare,
    required this.passengers,
    required this.paymentMethod,
    required this.issuedAt,
    this.seats = const [],
    this.passPeriod,
    this.validFrom,
    this.validUntil,
    this.validatedAt,
    this.validatedBy,
  });

  bool get isValidated => validatedAt != null;

  bool get isPass => kind == TicketKind.pass;

  /// Whether the entitlement is usable at [at].
  ///
  /// A pass is checked against its validity window; a journey ticket against a
  /// grace band around the scheduled departure, because buses run late and a
  /// ticket that stops working at the timetabled minute is useless.
  bool isUsableAt(DateTime at) {
    if (status == TicketStatus.cancelled) return false;
    if (isPass) {
      final from = validFrom;
      final until = validUntil;
      if (from == null || until == null) return false;
      return !at.isBefore(from) && !at.isAfter(until);
    }
    const graceBefore = Duration(hours: 4);
    const graceAfter = Duration(hours: 3);
    return at.isAfter(departsAt.subtract(graceBefore)) &&
        at.isBefore(arrivesAt.add(graceAfter));
  }

  /// Status recomputed against the clock.
  ///
  /// Stored status is authoritative for cancellation and validation; everything
  /// else is derived, so a ticket cannot sit at "Upcoming" three days after its
  /// bus left.
  TicketStatus statusAt(DateTime at) {
    if (status == TicketStatus.cancelled) return TicketStatus.cancelled;

    if (isPass) {
      final from = validFrom;
      final until = validUntil;
      if (from == null || until == null) return TicketStatus.expired;
      if (at.isBefore(from)) return TicketStatus.upcoming;
      if (at.isAfter(until)) return TicketStatus.expired;
      return TicketStatus.active;
    }

    if (at.isAfter(arrivesAt)) return TicketStatus.completed;
    if (at.isAfter(departsAt)) return TicketStatus.active;
    return TicketStatus.upcoming;
  }

  /// Days remaining on a pass. Null for a journey ticket.
  int? daysRemaining(DateTime at) {
    final until = validUntil;
    if (!isPass || until == null) return null;
    return math.max(0, until.difference(at).inDays);
  }

  /// Minutes until departure. Negative once the bus has gone.
  int minutesUntilDeparture(DateTime at) =>
      departsAt.difference(at).inMinutes;

  String get routeLabel => '$originName → $destinationName';

  /// Fare saved by the rider's concession.
  int get concession => math.max(0, baseFare - amountPaid);

  /// The QR payload.
  ///
  /// Deliberately self-describing and offline-verifiable: a conductor's device
  /// can check the reference, route, validity window, and a checksum without any
  /// network round-trip, which is the only way validation works in a tunnel or a
  /// dead zone. It carries no personal data beyond what is already printed on a
  /// paper ticket.
  String get qrPayload {
    final body = {
      'v': 1,
      'id': id,
      'ref': reference,
      'k': kind.name,
      'o': originStopId,
      'd': destinationStopId,
      'r': routeId,
      'c': serviceClassKey,
      'dep': departsAt.toIso8601String(),
      'arr': arrivesAt.toIso8601String(),
      'cat': riderCategory.name,
      'amt': amountPaid,
      'pax': passengers,
      if (validFrom != null) 'vf': validFrom!.toIso8601String(),
      if (validUntil != null) 'vu': validUntil!.toIso8601String(),
    };
    final encoded = jsonEncode(body);
    return 'BUSSPASS:$encoded:${_checksum(encoded)}';
  }

  /// Parse and verify a scanned payload.
  ///
  /// Returns null when the payload is not a BussPass ticket or the checksum
  /// fails, so a conductor sees "not a valid ticket" rather than a crash.
  static Ticket? fromQrPayload(String raw) {
    if (!raw.startsWith('BUSSPASS:')) return null;
    final lastColon = raw.lastIndexOf(':');
    if (lastColon <= 'BUSSPASS:'.length) return null;

    final body = raw.substring('BUSSPASS:'.length, lastColon);
    final checksum = raw.substring(lastColon + 1);
    if (_checksum(body) != checksum) return null;

    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return Ticket(
        id: json['id'] as String,
        reference: json['ref'] as String,
        kind: TicketKind.values.firstWhere(
          (k) => k.name == json['k'],
          orElse: () => TicketKind.single,
        ),
        status: TicketStatus.upcoming,
        originStopId: json['o'] as String? ?? '',
        originName: json['o'] as String? ?? '',
        destinationStopId: json['d'] as String? ?? '',
        destinationName: json['d'] as String? ?? '',
        routeId: json['r'] as String? ?? '',
        serviceClassKey: json['c'] as String? ?? 'Ordinary',
        departsAt: DateTime.parse(json['dep'] as String),
        arrivesAt: DateTime.parse(json['arr'] as String),
        distanceKm: 0,
        riderCategory: RiderCategory.values.firstWhere(
          (c) => c.name == json['cat'],
          orElse: () => RiderCategory.adult,
        ),
        amountPaid: (json['amt'] as num?)?.toInt() ?? 0,
        baseFare: (json['amt'] as num?)?.toInt() ?? 0,
        passengers: (json['pax'] as num?)?.toInt() ?? 1,
        paymentMethod: PaymentMethod.upi,
        issuedAt: DateTime.now(),
        validFrom: json['vf'] == null
            ? null
            : DateTime.tryParse(json['vf'] as String),
        validUntil: json['vu'] == null
            ? null
            : DateTime.tryParse(json['vu'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// FNV-1a over the payload, rendered base-36.
  ///
  /// This detects transcription and truncation errors, which is what a QR needs.
  /// It is explicitly **not** a signature — it does not prevent forgery, and a
  /// production deployment would sign with a depot key. Calling that out here so
  /// nobody mistakes the guarantee.
  static String _checksum(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(36).toUpperCase().padLeft(7, '0');
  }

  Ticket copyWith({
    TicketStatus? status,
    DateTime? validatedAt,
    String? validatedBy,
  }) =>
      Ticket(
        id: id,
        reference: reference,
        kind: kind,
        status: status ?? this.status,
        originStopId: originStopId,
        originName: originName,
        destinationStopId: destinationStopId,
        destinationName: destinationName,
        routeId: routeId,
        serviceClassKey: serviceClassKey,
        departsAt: departsAt,
        arrivesAt: arrivesAt,
        distanceKm: distanceKm,
        riderCategory: riderCategory,
        amountPaid: amountPaid,
        baseFare: baseFare,
        passengers: passengers,
        paymentMethod: paymentMethod,
        seats: seats,
        passPeriod: passPeriod,
        validFrom: validFrom,
        validUntil: validUntil,
        issuedAt: issuedAt,
        validatedAt: validatedAt ?? this.validatedAt,
        validatedBy: validatedBy ?? this.validatedBy,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'reference': reference,
        'kind': kind.name,
        'status': status.name,
        'origin_stop_id': originStopId,
        'origin_name': originName,
        'destination_stop_id': destinationStopId,
        'destination_name': destinationName,
        'route_id': routeId,
        'service_class': serviceClassKey,
        'departs_at': departsAt.toIso8601String(),
        'arrives_at': arrivesAt.toIso8601String(),
        'distance_km': distanceKm,
        'rider_category': riderCategory.name,
        'amount_paid': amountPaid,
        'base_fare': baseFare,
        'passengers': passengers,
        'payment_method': paymentMethod.name,
        'seats': seats,
        'pass_period': passPeriod?.name,
        'valid_from': validFrom?.toIso8601String(),
        'valid_until': validUntil?.toIso8601String(),
        'issued_at': issuedAt.toIso8601String(),
        'validated_at': validatedAt?.toIso8601String(),
        'validated_by': validatedBy,
      };

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        id: json['id'] as String,
        reference: json['reference'] as String? ?? '',
        kind: TicketKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => TicketKind.single,
        ),
        status: TicketStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TicketStatus.upcoming,
        ),
        originStopId: json['origin_stop_id'] as String? ?? '',
        originName: json['origin_name'] as String? ?? '',
        destinationStopId: json['destination_stop_id'] as String? ?? '',
        destinationName: json['destination_name'] as String? ?? '',
        routeId: json['route_id'] as String? ?? '',
        serviceClassKey: json['service_class'] as String? ?? 'Ordinary',
        departsAt: DateTime.parse(json['departs_at'] as String),
        arrivesAt: DateTime.parse(json['arrives_at'] as String),
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        riderCategory: RiderCategory.values.firstWhere(
          (c) => c.name == json['rider_category'],
          orElse: () => RiderCategory.adult,
        ),
        amountPaid: (json['amount_paid'] as num?)?.toInt() ?? 0,
        baseFare: (json['base_fare'] as num?)?.toInt() ?? 0,
        passengers: (json['passengers'] as num?)?.toInt() ?? 1,
        paymentMethod: PaymentMethod.values.firstWhere(
          (p) => p.name == json['payment_method'],
          orElse: () => PaymentMethod.upi,
        ),
        seats: (json['seats'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        passPeriod: json['pass_period'] == null
            ? null
            : PassPeriod.values.firstWhere(
                (p) => p.name == json['pass_period'],
                orElse: () => PassPeriod.monthly,
              ),
        validFrom: json['valid_from'] == null
            ? null
            : DateTime.tryParse(json['valid_from'] as String),
        validUntil: json['valid_until'] == null
            ? null
            : DateTime.tryParse(json['valid_until'] as String),
        issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? '') ??
            DateTime.now(),
        validatedAt: json['validated_at'] == null
            ? null
            : DateTime.tryParse(json['validated_at'] as String),
        validatedBy: json['validated_by'] as String?,
      );

  /// Generate a conductor-readable reference.
  ///
  /// Format `MS-XXXX-NNNN`: a depot-style prefix, four letters from a
  /// deliberately unambiguous alphabet (no I, O, 0, 1 — a conductor reading this
  /// aloud in a noisy bus cannot afford them), and four digits.
  static String generateReference(DateTime at, int seed) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rng = math.Random(
        at.millisecondsSinceEpoch ^ (seed * 0x9E3779B1));
    final letters = List.generate(
        4, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    final digits = (rng.nextInt(9000) + 1000).toString();
    return 'MS-$letters-$digits';
  }

  @override
  String toString() => 'Ticket($reference, $routeLabel, ${status.name})';
}

/// A place the rider has saved.
class SavedPlace {
  final String id;
  final String stopId;
  final String label;
  final SavedPlaceKind kind;
  final DateTime savedAt;

  const SavedPlace({
    required this.id,
    required this.stopId,
    required this.label,
    required this.kind,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'stop_id': stopId,
        'label': label,
        'kind': kind.name,
        'saved_at': savedAt.toIso8601String(),
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        id: json['id'] as String,
        stopId: json['stop_id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: SavedPlaceKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => SavedPlaceKind.other,
        ),
        savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

enum SavedPlaceKind {
  home('Home'),
  work('Work'),
  other('Saved');

  const SavedPlaceKind(this.label);
  final String label;
}

/// A recent origin-destination search.
class RecentSearch {
  final String originStopId;
  final String originName;
  final String destinationStopId;
  final String destinationName;
  final DateTime searchedAt;

  /// How many times this pair has been searched, so frequent routes float up.
  final int count;

  const RecentSearch({
    required this.originStopId,
    required this.originName,
    required this.destinationStopId,
    required this.destinationName,
    required this.searchedAt,
    this.count = 1,
  });

  String get key => '$originStopId>$destinationStopId';

  String get label => '$originName → $destinationName';

  RecentSearch bumped() => RecentSearch(
        originStopId: originStopId,
        originName: originName,
        destinationStopId: destinationStopId,
        destinationName: destinationName,
        searchedAt: DateTime.now(),
        count: count + 1,
      );

  Map<String, dynamic> toJson() => {
        'origin_stop_id': originStopId,
        'origin_name': originName,
        'destination_stop_id': destinationStopId,
        'destination_name': destinationName,
        'searched_at': searchedAt.toIso8601String(),
        'count': count,
      };

  factory RecentSearch.fromJson(Map<String, dynamic> json) => RecentSearch(
        originStopId: json['origin_stop_id'] as String? ?? '',
        originName: json['origin_name'] as String? ?? '',
        destinationStopId: json['destination_stop_id'] as String? ?? '',
        destinationName: json['destination_name'] as String? ?? '',
        searchedAt: DateTime.tryParse(json['searched_at'] as String? ?? '') ??
            DateTime.now(),
        count: (json['count'] as num?)?.toInt() ?? 1,
      );
}

/// A rating and comment left after a journey.
class JourneyFeedback {
  final String id;
  final String ticketId;
  final String routeId;

  /// 1 to 5.
  final int rating;

  /// Aspects the rider flagged.
  final Set<FeedbackTag> tags;
  final String comment;
  final DateTime submittedAt;

  const JourneyFeedback({
    required this.id,
    required this.ticketId,
    required this.routeId,
    required this.rating,
    required this.tags,
    required this.comment,
    required this.submittedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticket_id': ticketId,
        'route_id': routeId,
        'rating': rating,
        'tags': tags.map((t) => t.name).toList(),
        'comment': comment,
        'submitted_at': submittedAt.toIso8601String(),
      };

  factory JourneyFeedback.fromJson(Map<String, dynamic> json) =>
      JourneyFeedback(
        id: json['id'] as String,
        ticketId: json['ticket_id'] as String? ?? '',
        routeId: json['route_id'] as String? ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((e) => FeedbackTag.values.firstWhere(
                  (t) => t.name == e,
                  orElse: () => FeedbackTag.other,
                ))
            .toSet(),
        comment: json['comment'] as String? ?? '',
        submittedAt:
            DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// Aspects a rider can flag in feedback.
enum FeedbackTag {
  punctuality('Punctuality'),
  cleanliness('Cleanliness'),
  driving('Driving'),
  staffBehaviour('Staff behaviour'),
  crowding('Crowding'),
  comfort('Seat comfort'),
  safety('Safety'),
  other('Other');

  const FeedbackTag(this.label);
  final String label;
}

/// A night-halt alert raised by a conductor.
///
/// The plan's headline safety feature: passengers get stranded at food stops
/// because nobody tells them the bus is leaving.
class HaltAlert {
  final String id;
  final String routeId;
  final String stopName;
  final DateTime triggeredAt;

  /// When the bus resumes.
  final DateTime resumesAt;
  final String conductorId;

  /// Whether this rider has confirmed they are back on board.
  final bool confirmed;

  const HaltAlert({
    required this.id,
    required this.routeId,
    required this.stopName,
    required this.triggeredAt,
    required this.resumesAt,
    required this.conductorId,
    this.confirmed = false,
  });

  /// Minutes until departure, floored at zero.
  int minutesRemaining(DateTime at) =>
      math.max(0, resumesAt.difference(at).inMinutes);

  bool isActive(DateTime at) => at.isBefore(resumesAt);

  /// Escalation stage, matching the plan's 20-minute halt protocol:
  /// push at T+15, automated voice call at T+18.
  HaltStage stageAt(DateTime at) {
    final remaining = minutesRemaining(at);
    if (remaining <= 0) return HaltStage.departed;
    if (remaining <= 2) return HaltStage.finalCall;
    if (remaining <= 5) return HaltStage.boarding;
    return HaltStage.resting;
  }

  HaltAlert copyWith({bool? confirmed}) => HaltAlert(
        id: id,
        routeId: routeId,
        stopName: stopName,
        triggeredAt: triggeredAt,
        resumesAt: resumesAt,
        conductorId: conductorId,
        confirmed: confirmed ?? this.confirmed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'route_id': routeId,
        'stop_name': stopName,
        'triggered_at': triggeredAt.toIso8601String(),
        'resumes_at': resumesAt.toIso8601String(),
        'conductor_id': conductorId,
        'confirmed': confirmed,
      };

  factory HaltAlert.fromJson(Map<String, dynamic> json) => HaltAlert(
        id: json['id'] as String,
        routeId: json['route_id'] as String? ?? '',
        stopName: json['stop_name'] as String? ?? '',
        triggeredAt:
            DateTime.tryParse(json['triggered_at'] as String? ?? '') ??
                DateTime.now(),
        resumesAt: DateTime.tryParse(json['resumes_at'] as String? ?? '') ??
            DateTime.now(),
        conductorId: json['conductor_id'] as String? ?? '',
        confirmed: json['confirmed'] as bool? ?? false,
      );
}

/// Stage of a night halt.
enum HaltStage {
  /// Plenty of time.
  resting('Rest stop', 'The bus is halted here'),

  /// Return to the bus.
  boarding('Boarding soon', 'Please return to the bus'),

  /// Leaving imminently.
  finalCall('Final call', 'The bus is about to leave'),

  /// Gone.
  departed('Departed', 'The bus has resumed its journey');

  const HaltStage(this.label, this.message);
  final String label;
  final String message;
}

/// A completed journey, for history and stats.
class JourneyRecord {
  final String id;
  final String ticketId;
  final String originName;
  final String destinationName;
  final String serviceClassKey;
  final DateTime departedAt;
  final DateTime arrivedAt;
  final double distanceKm;
  final int farePaid;

  /// Minutes late on arrival. Negative means early.
  final int delayMinutes;

  const JourneyRecord({
    required this.id,
    required this.ticketId,
    required this.originName,
    required this.destinationName,
    required this.serviceClassKey,
    required this.departedAt,
    required this.arrivedAt,
    required this.distanceKm,
    required this.farePaid,
    this.delayMinutes = 0,
  });

  int get durationMinutes => arrivedAt.difference(departedAt).inMinutes;

  String get durationLabel => Schedule.formatDuration(durationMinutes);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticket_id': ticketId,
        'origin_name': originName,
        'destination_name': destinationName,
        'service_class': serviceClassKey,
        'departed_at': departedAt.toIso8601String(),
        'arrived_at': arrivedAt.toIso8601String(),
        'distance_km': distanceKm,
        'fare_paid': farePaid,
        'delay_minutes': delayMinutes,
      };

  factory JourneyRecord.fromJson(Map<String, dynamic> json) => JourneyRecord(
        id: json['id'] as String,
        ticketId: json['ticket_id'] as String? ?? '',
        originName: json['origin_name'] as String? ?? '',
        destinationName: json['destination_name'] as String? ?? '',
        serviceClassKey: json['service_class'] as String? ?? 'Ordinary',
        departedAt: DateTime.parse(json['departed_at'] as String),
        arrivedAt: DateTime.parse(json['arrived_at'] as String),
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        farePaid: (json['fare_paid'] as num?)?.toInt() ?? 0,
        delayMinutes: (json['delay_minutes'] as num?)?.toInt() ?? 0,
      );
}
