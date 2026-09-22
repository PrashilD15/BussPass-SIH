/// Build a minimal single-leg itinerary for *tracking* an already-running bus.
///
/// Shared by the map tab's "Track this bus" and the home boarding prompt so
/// the live-nav screen always gets a well-formed leg, whether the rider picked
/// the bus from the map or the app inferred they're aboard it.
library;

import 'package:busspass/core/math/eta_engine.dart';
import 'package:busspass/core/math/fare_engine.dart';
import 'package:busspass/core/math/journey_planner.dart';
import 'package:busspass/core/math/schedule.dart';
import 'package:busspass/data/models/live_bus.dart';
import 'package:busspass/data/models/network_models.dart';

Itinerary buildTrackingItinerary(
  TransitNetwork network,
  TransitRoute route,
  LiveBus bus,
) {
  final serviceClass = ServiceClassCatalog.byKey(bus.busType);
  final boardRef = route.stops.first;
  final alightRef = route.stops.last;
  final estimate = EtaEngine.estimate(
    distanceKm: route.distanceKm,
    serviceClass: serviceClass,
    intermediateStops: route.stops.length - 2,
    departureMinuteOfDay: Schedule.minuteOfDay(bus.scheduledDeparture),
  );
  return Itinerary(
    legs: [
      JourneyLeg(
        route: route,
        service: TransitService(
          id: bus.serviceId,
          routeId: route.id,
          busType: bus.busType,
          source: 'timetable',
          fromStopId: route.originStopId,
          departures: [Schedule.minuteOfDay(bus.scheduledDeparture)],
        ),
        boardStop: network.stopById(boardRef.stopId)!,
        alightStop: network.stopById(alightRef.stopId)!,
        boardSeq: boardRef.seq,
        alightSeq: alightRef.seq,
        distanceKm: route.distanceKm,
        departsAt: bus.scheduledDeparture,
        arrivesAt: bus.scheduledDeparture
            .add(Duration(minutes: estimate.totalMinutes)),
        estimate: estimate,
        fare: FareEngine.compute(
          distanceKm: route.distanceKm,
          serviceClass: serviceClass,
        ).baseFare,
        intermediateStops: route.intermediateStops,
      ),
    ],
    transfers: const [],
  );
}
