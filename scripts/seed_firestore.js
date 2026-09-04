// ─────────────────────────────────────────────────────────────────────────────
// MSRTC Firestore Seed Script (real data) — ENHANCED with per-stop pricing
// Run with: node scripts/seed_firestore.js
// Requires: npm install firebase-admin
//
// Consumes scripts/msrtc_data.js (real stands + route graph + MSRTC fare model)
// and writes to Firestore with schema matching busspass/lib/data/models/bus_models.dart
//
// NEW in this version:
//  1. Resolves via_stops to EXACT lat/lng (via STANDS + WAYPOINTS) so the map
//     polyline follows the actual road corridor instead of a straight line.
//  2. Computes cumulative distance at each stop (scaled to official route km).
//  3. Computes the MSRTC stage-based fare at EVERY stop for EVERY bus type.
//  4. Writes a `route_fares` collection: one doc per route with a per stop-pair
//     fare matrix (per bus type) + total distance + cumulative stages.
//  5. Adds a `stops` array (with lat/lng + cumulative km) to each route doc so
//     the Flutter app can render an accurate polyline and intermediate markers.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  BUS_TYPES,
  computeFare,
  durationHrs,
  STANDS,
  WAYPOINTS,
  ROUTES,
} = require('./msrtc_data.js');

// Guard: do not run without a real (non-placeholder) service account key.
const KEY_PATH = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(KEY_PATH)) {
  console.error('❌ serviceAccountKey.json not found in scripts/.');
  console.error('   Add your Firebase service account key, then re-run.');
  process.exit(1);
}

const serviceAccount = require(KEY_PATH);

initializeApp({
  credential: cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const db = getFirestore();

// ── First / last bus estimates based on journey family and bus type ─────────
function busWindows(km) {
  if (km > 600)
    return { first: '06:00 PM', last: '09:00 PM' }; // overnight long-haul
  if (km > 250)
    return { first: '05:30 AM', last: '10:30 PM' };
  if (km > 100)
    return { first: '05:00 AM', last: '10:00 PM' };
  return { first: '05:30 AM', last: '10:30 PM' };
}

// ── Geography helpers ────────────────────────────────────────────────────────
const R = 6371; // Earth radius (km)

function haversineKm(a, b) {
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// ── Resolve a via-stop name to coordinates ───────────────────────────────────
// Look in STANDS by city (case-insensitive, accepts partial match), then WAYPOINTS.
function resolveStop(cityName) {
  const q = String(cityName).trim().toLowerCase();
  const stand = STANDS.find(
    (s) => s.city.toLowerCase() === q || s.name.toLowerCase().includes(q)
  );
  if (stand) return { id: stand.id, name: stand.name, city: stand.city, lat: stand.lat, lng: stand.lng };
  const wp = WAYPOINTS[q];
  if (wp) return { id: q, name: titleCase(q), city: titleCase(q), lat: wp.lat, lng: wp.lng };
  return null;
}

function titleCase(s) {
  return s
    .replace(/([A-Z])/g, ' $1')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();
}// ── Build ordered stop sequence with cumulative distance ─────────────────────
// Returns an array of { name, city, id, lat, lng, seq, cumKm } where cumKm is
// the distance from the origin measured along the corridor. The intermediate
// distances are proportionally scaled from the straight-line haversine ratios
// so the TOTAL equals the official route distance_km.
function buildStops(origin, dest, viaCities, routeKm) {
  const sequence = [origin];
  for (const v of viaCities) {
    const resolved = resolveStop(v);
    if (resolved) sequence.push(resolved);
  }
  sequence.push(dest);

  // Raw straight-line segment lengths between consecutive stops.
  const rawSegs = [];
  for (let i = 0; i < sequence.length - 1; i++) {
    rawSegs.push(haversineKm(sequence[i], sequence[i + 1]));
  }
  const rawTotal = rawSegs.reduce((a, b) => a + b, 0);

  // Scale factor to hit the official route distance.
  const scale = rawTotal > 0 ? routeKm / rawTotal : 1;

  // Build cumulative km + seq.
  const stops = [];
  let cum = 0;
  for (let i = 0; i < sequence.length; i++) {
    stops.push({
      id: sequence[i].id,
      name: sequence[i].name,
      city: sequence[i].city,
      lat: sequence[i].lat,
      lng: sequence[i].lng,
      seq: i + 1,
      cumKm: Math.round((i === 0 ? 0 : cum) * 10) / 10,
    });
    if (i < rawSegs.length) cum += rawSegs[i] * scale;
  }
  // Snap final cumulative to official distance.
  stops[stops.length - 1].cumKm = routeKm;
  return stops;
}

// ── MSRTC fare matrix per stop-pair for a route ──────────────────────────────
// msrtc fares are stage-based: fare between stop i and stop j depends only on
// the distance (cumKm[j] - cumKm[i]) — cheaper than full-fare because it's the
// actual distance between those two points, computed via the per-6km stage model.
function buildFareMatrix(stops, busTypes) {
  const fares = {};
  for (let i = 0; i < stops.length; i++) {
    for (let j = i + 1; j < stops.length; j++) {
      const dist = stops[j].cumKm - stops[i].cumKm;
      const fromId = stops[i].id;
      const toId = stops[j].id;
      fares[`${fromId}__${toId}`] = {
        from: stops[i].city,
        to: stops[j].city,
        fromStopId: fromId,
        toStopId: toId,
        fromSeq: stops[i].seq,
        toSeq: stops[j].seq,
        distanceKm: Math.round(dist),
        byType: Object.fromEntries(
          busTypes.map((t) => [t, computeFare(dist, t)])
        ),
      };
    }
  }
  return fares;
}

// ── Build bus stops collection ───────────────────────────────────────────────
function buildBusStops() {
  return STANDS.map((s) => ({
    id: s.id,
    name: s.name,
    city: s.city,
    depot: s.depot,
    lat: s.lat,
    lng: s.lng,
  }));
}

// ── Build routes collection (with `stops` for map polyline) ──────────────────
function buildRoutes() {
  const routes = [];
  const stopById = Object.fromEntries(STANDS.map((s) => [s.id, s]));

  for (const r of ROUTES) {
    const [originStopId, destStopId, km, busTypes, viaStops] = r;
    const origin = stopById[originStopId];
    const dest = stopById[destStopId];
    if (!origin || !dest) continue;

    // fare_min = cheapest available bus, fare_max = most expensive (full route)
    const fares = busTypes.map((t) => computeFare(km, t));
    const fareMin = Math.min(...fares);
    const fareMax = Math.max(...fares);

    const { first, last } = busWindows(km);
    const stops = buildStops(origin, dest, viaStops, km);

    routes.push({
      id: `${originStopId}-${destStopId}`,
      name: `${origin.city} – ${dest.city}`,
      origin_stop_id: origin.id,
      destination_stop_id: dest.id,
      origin_city: origin.city,
      destination_city: dest.city,
      distance_km: km,
      duration_hrs: durationHrs(km),
      fare_min: fareMin,
      fare_max: fareMax,
      bus_types: busTypes,
      via_stops: viaStops,
      // NEW: ordered stops with coords + cumulative km (for accurate polyline)
      stops: stops.map((s) => ({
        stop_id: s.id,
        name: s.name,
        city: s.city,
        lat: s.lat,
        lng: s.lng,
        seq: s.seq,
        cum_km: s.cumKm,
      })),
      first_bus: first,
      last_bus: last,
    });
  }
  return routes;
}

// ── Build route_fares collection (per stop-pair fare matrix) ─────────────────
function buildRouteFares(routes) {
  const fareDocs = [];
  for (const route of routes) {
    const stops = route.stops.map((s) => ({
      id: s.stop_id,
      city: s.city,
      seq: s.seq,
      cumKm: s.cum_km,
      lat: s.lat,
      lng: s.lng,
    }));
    const matrix = buildFareMatrix(stops, route.bus_types);

    fareDocs.push({
      id: route.id,
      route_name: route.name,
      origin_stop_id: route.origin_stop_id,
      destination_stop_id: route.destination_stop_id,
      origin_city: route.origin_city,
      destination_city: route.destination_city,
      distance_km: route.distance_km,
      bus_types: route.bus_types,
      fare_min: route.fare_min,
      fare_max: route.fare_max,
      total_stops: stops.length,
      by_type: Object.fromEntries(
        route.bus_types.map((t) => [t, computeFare(route.distance_km, t)])
      ),
      // Map of "fromStopId__toStopId" -> segment fare info
      segments: matrix,
    });
  }
  return fareDocs;
}

// ── Cleanup stale docs (removed src) so a re-run never leaves data orphaned ──
async function cleanupStale(collectionName, validIds) {
  const snap = await db.collection(collectionName).get();
  const stale = snap.docs.filter((d) => !validIds.has(d.id));
  const batch = db.batch();
  for (const doc of stale) batch.delete(doc.ref);
  if (stale.length > 0) await batch.commit();
  return stale.length;
}

// ── Seed ─────────────────────────────────────────────────────────────────────
async function seedData() {
  console.log('🚌 Starting MSRTC Firestore seed (enhanced w/ per-stop fares)...\n');

  const busStops = buildBusStops();
  const routes = buildRoutes();
  const routeFares = buildRouteFares(routes);

  // Remove documents that are no longer in the dataset (e.g. old placeholder IDs).
  const stopIds = new Set(STANDS.map((s) => s.id));
  const routeIds = new Set(ROUTES.map((r) => `${r[0]}-${r[1]}`));
  const removedStops = await cleanupStale('bus_stops', stopIds);
  const removedRoutes = await cleanupStale('routes', routeIds);
  const removedFares = await cleanupStale('route_fares', routeIds);
  if (removedStops) console.log(`🗑️  Removed ${removedStops} stale bus stops`);
  if (removedRoutes) console.log(`🗑️  Removed ${removedRoutes} stale routes`);
  if (removedFares) console.log(`🗑️  Removed ${removedFares} stale route_fares`);

  console.log(`📍 Seeding ${busStops.length} bus stops...`);
  const stopBatch = db.batch();
  for (const stop of busStops) {
    const { id, ...data } = stop;
    stopBatch.set(db.collection('bus_stops').doc(id), data);
  }
  await stopBatch.commit();
  console.log('✅ Bus stops seeded!\n');

  console.log(`🗺️  Seeding ${routes.length} routes (with stop coordinates)...`);
  const routeBatch = db.batch();
  for (const route of routes) {
    const { id, ...data } = route;
    routeBatch.set(db.collection('routes').doc(id), data);
  }
  await routeBatch.commit();
  console.log('✅ Routes seeded!\n');

  console.log(`💰 Seeding ${routeFares.length} route_fares docs (per stop-pair)...`);
  const fareBatch = db.batch();
  for (const doc of routeFares) {
    const { id, ...data } = doc;
    fareBatch.set(db.collection('route_fares').doc(id), data);
  }
  await fareBatch.commit();

  let segmentTotal = 0;
  for (const d of routeFares) segmentTotal += Object.keys(d.segments).length;
  console.log(`✅ Route fares seeded (${segmentTotal} stop-pair segments total)!\n`);

  console.log('🎉 Firestore seed complete!');
  console.log(`   ${busStops.length} bus stops`);
  console.log(`   ${routes.length} routes`);
  console.log(`   ${routeFares.length} route_fares docs with ${segmentTotal} fare segments`);
  process.exit(0);
}

seedData().catch((err) => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
