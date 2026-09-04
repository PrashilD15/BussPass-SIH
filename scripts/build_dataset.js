// ─────────────────────────────────────────────────────────────────────────────
// Offline dataset builder for the BussPass Flutter app.
//
//   node scripts/build_dataset.js
//   → busspass/assets/data/network.json
//
// Merges three sources into one bundle the app can load with zero network:
//   1. scripts/msrtc_data.js      — curated stands + intercity corridors with
//                                   official government road distances.
//   2. master_timetables.json     — 1,019 scraped depot timetables (real
//                                   departure times, destinations, distances).
//   3. scripts/depot_origins.js   — slug → stand resolution for those scrapes.
//
// Fares are deliberately NOT baked in. The Dart `FareEngine` computes them from
// the stage model at runtime, so the tariff table lives in exactly one place and
// a fare revision is a one-line change rather than a re-seed.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');

const { STANDS, WAYPOINTS, ROUTES } = require('./msrtc_data.js');
const { DEPOT_ORIGINS, normaliseBusType } = require('./depot_origins.js');

const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, 'busspass', 'assets', 'data', 'network.json');

// ── Service class catalogue ──────────────────────────────────────────────────
// `stageRate` is the MSRTC per-6km tariff (18-Jul-2026 revision).
// `cruiseKmph` / `dwellMin` / `seats` drive the ETA and occupancy engines.
// Speeds reflect service class: an Ordinary bus halts at every village, a
// Shivneri runs expressway-only with two comfort breaks.
const SERVICE_CLASSES = [
  {
    key: 'Ordinary', label: 'Ordinary', marathi: 'साधी',
    stageRate: 11.40, ac: false, sleeper: false, tier: 1,
    cruiseKmph: 46, dwellMin: 2.0, stopDensity: 1.0, seats: 52,
  },
  {
    key: 'Semi Luxury', label: 'Semi Luxury (Hirkani)', marathi: 'हिरकणी',
    stageRate: 13.65, ac: false, sleeper: false, tier: 2,
    cruiseKmph: 52, dwellMin: 1.5, stopDensity: 0.6, seats: 45,
  },
  {
    key: 'Shivshahi', label: 'Shivshahi AC Seater', marathi: 'शिवशाही',
    stageRate: 14.20, ac: true, sleeper: false, tier: 3,
    cruiseKmph: 56, dwellMin: 1.2, stopDensity: 0.4, seats: 43,
  },
  {
    key: 'Shivshahi Sleeper', label: 'Shivshahi AC Sleeper', marathi: 'शिवशाही शयनयान',
    stageRate: 15.35, ac: true, sleeper: true, tier: 3,
    cruiseKmph: 56, dwellMin: 1.2, stopDensity: 0.3, seats: 30,
  },
  {
    key: 'Sleeper Seater', label: 'Ordinary Sleeper-Seater', marathi: 'शयनयान-आसनी',
    stageRate: 15.50, ac: false, sleeper: true, tier: 2,
    cruiseKmph: 50, dwellMin: 1.5, stopDensity: 0.5, seats: 36,
  },
  {
    key: 'Ordinary Sleeper', label: 'Ordinary Sleeper', marathi: 'शयनयान',
    stageRate: 16.75, ac: false, sleeper: true, tier: 2,
    cruiseKmph: 50, dwellMin: 1.5, stopDensity: 0.4, seats: 30,
  },
  {
    key: 'Shivneri', label: 'Shivneri AC Seater', marathi: 'शिवनेरी',
    stageRate: 21.25, ac: true, sleeper: false, tier: 4,
    cruiseKmph: 62, dwellMin: 1.0, stopDensity: 0.2, seats: 45,
  },
  {
    key: 'Shivneri Sleeper', label: 'Shivneri AC Sleeper', marathi: 'शिवनेरी शयनयान',
    stageRate: 25.35, ac: true, sleeper: true, tier: 4,
    cruiseKmph: 62, dwellMin: 1.0, stopDensity: 0.2, seats: 30,
  },
];

// `Sleeper` appears as a bare bus type on legacy long-haul routes.
const CLASS_ALIASES = { Sleeper: 'Ordinary Sleeper' };

const CLASS_KEYS = new Set(SERVICE_CLASSES.map((c) => c.key));

function canonicalClass(key) {
  const resolved = CLASS_ALIASES[key] || key;
  return CLASS_KEYS.has(resolved) ? resolved : 'Ordinary';
}

// ── Extra towns needed to resolve scraped destinations ───────────────────────
// Only towns that are unambiguous and carry meaningful traffic are added.
// Ambiguous names (KARJAT — Raigad or Ahmednagar? RAJAPUR — Ratnagiri or
// Solapur?) are intentionally left unresolved rather than guessed.
const EXTRA_PLACES = [
  { id: 'trimbakeshwar', name: 'Trimbakeshwar Bus Stand', city: 'Trimbakeshwar', lat: 19.9333, lng: 73.5333, district: 'Nashik' },
  { id: 'paithan', name: 'Paithan Bus Stand', city: 'Paithan', lat: 19.4800, lng: 75.3800, district: 'Chhatrapati Sambhaji Nagar' },
  { id: 'vaijapur', name: 'Vaijapur Bus Stand', city: 'Vaijapur', lat: 19.9260, lng: 74.7280, district: 'Chhatrapati Sambhaji Nagar' },
  { id: 'shegaon', name: 'Shegaon Bus Stand', city: 'Shegaon', lat: 20.7936, lng: 76.6947, district: 'Buldhana' },
  { id: 'rahuri', name: 'Rahuri Bus Stand', city: 'Rahuri', lat: 19.3900, lng: 74.6500, district: 'Ahmednagar' },
  { id: 'niphad', name: 'Niphad Bus Stand', city: 'Niphad', lat: 20.0833, lng: 74.1103, district: 'Nashik' },
  { id: 'chandwad', name: 'Chandwad Bus Stand', city: 'Chandwad', lat: 20.3300, lng: 74.2400, district: 'Nashik' },
  { id: 'chalisgaon', name: 'Chalisgaon Bus Stand', city: 'Chalisgaon', lat: 20.4600, lng: 75.0100, district: 'Jalgaon' },
  { id: 'amalner', name: 'Amalner Bus Stand', city: 'Amalner', lat: 21.0400, lng: 75.0600, district: 'Jalgaon' },
  { id: 'pachora', name: 'Pachora Bus Stand', city: 'Pachora', lat: 20.6700, lng: 75.3500, district: 'Jalgaon' },
  { id: 'shirpur', name: 'Shirpur Bus Stand', city: 'Shirpur', lat: 21.3500, lng: 74.8800, district: 'Dhule' },
  { id: 'chopda', name: 'Chopda Bus Stand', city: 'Chopda', lat: 21.2500, lng: 75.3000, district: 'Jalgaon' },
  { id: 'tuljapur', name: 'Tuljapur Bus Stand', city: 'Tuljapur', lat: 18.0100, lng: 76.0700, district: 'Dharashiv' },
  { id: 'akkalkot', name: 'Akkalkot Bus Stand', city: 'Akkalkot', lat: 17.5200, lng: 76.2000, district: 'Solapur' },
  { id: 'baramati', name: 'Baramati Bus Stand', city: 'Baramati', lat: 18.1514, lng: 74.5815, district: 'Pune' },
  { id: 'kalyan', name: 'Kalyan Bus Stand', city: 'Kalyan', lat: 19.2403, lng: 73.1305, district: 'Thane' },
  { id: 'bhandardara', name: 'Bhandardara Bus Stop', city: 'Bhandardara', lat: 19.5400, lng: 73.7500, district: 'Ahmednagar' },
  { id: 'surgana', name: 'Surgana Bus Stand', city: 'Surgana', lat: 20.5600, lng: 73.6300, district: 'Nashik' },
  { id: 'vani', name: 'Vani Bus Stand', city: 'Vani', lat: 20.3200, lng: 73.8900, district: 'Nashik' },
  { id: 'bhagur', name: 'Bhagur Bus Stand', city: 'Bhagur', lat: 19.9200, lng: 73.8900, district: 'Nashik' },
  { id: 'ghoti', name: 'Ghoti Bus Stand', city: 'Ghoti', lat: 19.7200, lng: 73.6300, district: 'Nashik' },
  { id: 'surat', name: 'Surat Central Bus Stand', city: 'Surat', lat: 21.1702, lng: 72.8311, district: 'Surat (GJ)' },
];

// Scraped destination string → canonical stop id.
const DESTINATION_ALIASES = {
  'ahemadnagar': 'ahmednagar',
  'ahmednagar': 'ahmednagar',
  'nagar': 'ahmednagar',
  'a nagar': 'ahmednagar',
  'chattrapati sambhajinagar': 'csn',
  'chatrapati sambhajinagar': 'csn',
  'sambhajinagar': 'csn',
  'aurangabad': 'csn',
  'swargate': 'pune-swargate',
  'pune station': 'pune-station',
  'shivajinagar': 'pune-shivajinagar',
  'pune': 'pune-swargate',
  'mumbai': 'mumbai-central',
  'mumbai central': 'mumbai-central',
  'dadar': 'mumbai-dadar',
  'borivali': 'mumbai-borivali',
  'nashik': 'nashik-cbs',
  'nasik': 'nashik-cbs',
  'manmad': 'nashik-manmad',
  'tryambakeshwar': 'trimbakeshwar',
  'trimbakeshwar': 'trimbakeshwar',
  'ammalner': 'amalner',
  'amalner': 'amalner',
  'chopada': 'chopda',
  'newasa': 'nevasa',
  'nevasa': 'nevasa',
  'akole': 'akole',
  'osmanabad': 'dharashiv',
  'dharashiv': 'dharashiv',
  'oros': 'sindhudurg-oras',
  'alibag': 'raigad-alibag',
  'sinnar': 'sinnar',
  'yeola': 'yeola',
  'satana': 'satana',
  'punad dam': null,   // reservoir, no stand
  'malgaon': null,     // ambiguous: Malegaon or Malgaon village
  'karjat': null,      // ambiguous: Raigad or Ahmednagar
  'rajapur': null,     // ambiguous: Ratnagiri or Solapur
};

// ── Geometry ─────────────────────────────────────────────────────────────────
const EARTH_R_KM = 6371.0088;

function haversineKm(a, b) {
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_R_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

const round1 = (n) => Math.round(n * 10) / 10;
const round4 = (n) => Math.round(n * 1e4) / 1e4;

function titleCase(s) {
  return String(s)
    .toLowerCase()
    .replace(/_/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// ── Stop registry ────────────────────────────────────────────────────────────
// A single map keyed by stop id, with a secondary index on normalised
// name/city so scraped strings can be resolved.
const stops = new Map();
const nameIndex = new Map();

function normKey(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function registerStop(stop) {
  const existing = stops.get(stop.id);
  if (existing) {
    // Merge: prefer richer metadata, never overwrite coordinates.
    existing.district = existing.district || stop.district || '';
    existing.depot = existing.depot || stop.depot || '';
    return existing;
  }
  const record = {
    id: stop.id,
    name: stop.name,
    city: stop.city,
    depot: stop.depot || stop.city,
    district: stop.district || '',
    lat: round4(stop.lat),
    lng: round4(stop.lng),
    tier: stop.tier || 1,
  };
  stops.set(record.id, record);
  for (const key of [normKey(record.city), normKey(record.name), normKey(record.id)]) {
    if (key && !nameIndex.has(key)) nameIndex.set(key, record.id);
  }
  return record;
}

function resolveStopId(raw) {
  if (raw == null) return null;
  const cleaned = String(raw).trim();
  if (!cleaned) return null;

  const aliasKey = cleaned.toLowerCase().replace(/\s+/g, ' ');
  if (Object.prototype.hasOwnProperty.call(DESTINATION_ALIASES, aliasKey)) {
    return DESTINATION_ALIASES[aliasKey]; // may be null = deliberately unresolved
  }
  const direct = nameIndex.get(normKey(cleaned));
  return direct || null;
}

// Seed the registry: curated stands are the highest-quality source.
for (const s of STANDS) {
  registerStop({ ...s, tier: 3 });
}
// Depot origins from the timetable scrape.
for (const slug of Object.keys(DEPOT_ORIGINS)) {
  const origin = DEPOT_ORIGINS[slug];
  if (origin) registerStop({ ...origin, tier: 2 });
}
// Extra towns for destination resolution.
for (const p of EXTRA_PLACES) {
  registerStop({ ...p, depot: p.city, tier: 2 });
}
// Corridor waypoints — needed for polyline shape even when not a full stand.
for (const key of Object.keys(WAYPOINTS)) {
  const wp = WAYPOINTS[key];
  if (nameIndex.has(normKey(key))) continue;
  registerStop({
    id: key, name: `${titleCase(key)} Bus Stop`, city: titleCase(key),
    depot: titleCase(key), lat: wp.lat, lng: wp.lng, tier: 1,
  });
}

// ── Corridor stop sequences ──────────────────────────────────────────────────
// Intermediate distances are proportionally scaled from great-circle ratios so
// the cumulative total lands exactly on the official road distance. This keeps
// per-segment fares self-consistent: sum(segment km) === route km.
//
// One invariant must hold or every downstream fare is wrong: **no segment's
// along-route distance may be shorter than the straight line between its two
// stops**. That happens whenever the declared route distance is less than the
// sum of the via-leg straight lines — either the published distance is stale or
// a via-stop resolved to a place that is not actually on the corridor. In that
// case the declared distance is raised to the geometric minimum and reported,
// rather than silently producing segments that violate geometry.
const geometryAdjustments = [];

function buildStopSequence(originId, destId, viaNames, routeKm, label) {
  const ids = [originId];
  for (const via of viaNames) {
    const resolved = resolveStopId(via);
    if (resolved && resolved !== ids[ids.length - 1] && resolved !== destId) {
      ids.push(resolved);
    }
  }
  ids.push(destId);

  const nodes = ids.map((id) => stops.get(id)).filter(Boolean);
  if (nodes.length < 2) return null;

  const legs = [];
  for (let i = 0; i < nodes.length - 1; i++) {
    legs.push(haversineKm(nodes[i], nodes[i + 1]));
  }
  const rawTotal = legs.reduce((a, b) => a + b, 0);

  // Enforce the geometric floor.
  let effectiveKm = routeKm;
  if (rawTotal > 0 && routeKm < rawTotal * MIN_DETOUR_FACTOR) {
    effectiveKm = round1(rawTotal * MIN_DETOUR_FACTOR);
    geometryAdjustments.push(
      `${label || `${originId}->${destId}`}: declared ${routeKm} km raised to ` +
      `${effectiveKm} km (via-leg straight lines total ${rawTotal.toFixed(0)} km)`
    );
  }

  const scale = rawTotal > 0 ? effectiveKm / rawTotal : 1;

  let cum = 0;
  const sequence = nodes.map((node, i) => {
    const entry = {
      stop_id: node.id,
      name: node.name,
      city: node.city,
      lat: node.lat,
      lng: node.lng,
      seq: i + 1,
      cum_km: i === 0 ? 0 : round1(cum),
    };
    if (i < legs.length) cum += legs[i] * scale;
    return entry;
  });
  sequence[sequence.length - 1].cum_km = round1(effectiveKm);
  return { stops: sequence, distanceKm: round1(effectiveKm) };
}

/// Roads are never straight: the along-route distance between two stops must
/// exceed their great-circle separation by at least this factor.
const MIN_DETOUR_FACTOR = 1.02;


// ── Departure generation for curated corridors ───────────────────────────────
// The curated ROUTES carry no timetable, so a plausible one is synthesised from
// the service window. Headway widens with distance and premium class: an
// Ordinary Pune–Mumbai runs every 40 min, a Shivneri Nagpur–Mumbai runs twice.
// `seed` makes the output deterministic so rebuilds produce identical assets.
function serviceWindow(km) {
  if (km > 600) return { first: 17 * 60, last: 22 * 60 };      // overnight only
  if (km > 350) return { first: 6 * 60, last: 22 * 60 };
  if (km > 150) return { first: 5 * 60 + 30, last: 22 * 60 + 30 };
  return { first: 5 * 60, last: 23 * 60 };
}

function headwayMinutes(km, classKey) {
  const cls = SERVICE_CLASSES.find((c) => c.key === classKey);
  const tier = cls ? cls.tier : 1;
  const base = km <= 120 ? 30 : km <= 250 ? 45 : km <= 450 ? 90 : 180;
  return Math.round(base * (1 + 0.55 * (tier - 1)));
}

function generateDepartures(km, classKey, seed) {
  const { first, last } = serviceWindow(km);
  const headway = headwayMinutes(km, classKey);
  // Deterministic per-(route, class) phase offset so classes don't all leave
  // on the same minute.
  const offset = seed % headway;
  const out = [];
  for (let t = first + offset; t <= last; t += headway) {
    out.push(t % 1440);
  }
  if (out.length === 0) out.push(first);
  return out;
}

function hashSeed(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

// ── Departure-time parsing for scraped timetables ────────────────────────────
const MARATHI_DIGITS = { '०': '0', '१': '1', '२': '2', '३': '3', '४': '4', '५': '5', '६': '6', '७': '7', '८': '8', '९': '9' };

function parseTimes(raw) {
  let s = String(raw).trim();
  if (!s) return [];

  let forced = null; // 0 = AM, 1 = PM
  if (/सकाळी/.test(s)) forced = 0;
  else if (/दुपारी|संध्याकाळी|रात्री/.test(s)) forced = 1;
  if (/\bAM\b/i.test(s)) forced = 0;
  if (/\bPM\b/i.test(s)) forced = 1;

  s = s.replace(/[०-९]/g, (c) => MARATHI_DIGITS[c] || c);
  // The scrape contains OCR damage like "9:)0 AM" — treat any non-digit inside
  // the minute field as a zero rather than discarding the departure.
  s = s.replace(/(\d{1,2})\s*[:.]\s*([)(\[\]oO])(\d)/g, '$1:0$3');
  s = s.replace(/(\d{1,2})\s*[:.]\s*(\d)([)(\[\]oO])/g, '$1:$20');

  const out = [];
  const re = /(\d{1,2})\s*[:.]\s*(\d{1,2})\s*([AaPp])?\.?[Mm]?\.?/g;
  let m;
  while ((m = re.exec(s)) !== null) {
    let hour = parseInt(m[1], 10);
    const minute = parseInt(m[2], 10);
    if (Number.isNaN(hour) || Number.isNaN(minute) || minute > 59) continue;

    let period = forced;
    if (m[3]) period = m[3].toLowerCase() === 'p' ? 1 : 0;

    if (period === 1 && hour < 12) hour += 12;
    if (period === 0 && hour === 12) hour = 0;
    if (hour === 24) hour = 0;
    if (hour > 23) continue;
    out.push(hour * 60 + minute);
  }
  return out;
}

function parseKm(raw) {
  if (raw == null) return null;
  const s = String(raw).replace(/[०-९]/g, (c) => MARATHI_DIGITS[c] || c);
  const m = s.match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const km = parseFloat(m[1]);
  return km > 0 && km < 2000 ? km : null;
}

// Split "PUNE VIA SANGAMNER" → { destination: 'PUNE', via: ['SANGAMNER'] }
function splitVia(destination) {
  const parts = String(destination).split(/\s+VIA\s+/i);
  const head = parts[0].trim();
  const via = parts
    .slice(1)
    .join(' ')
    .split(/[,&]|\s+AND\s+/i)
    .map((v) => v.trim())
    .filter(Boolean);
  return { destination: head, via };
}

// ── Build routes + services ──────────────────────────────────────────────────
const routes = new Map();
const services = [];
const timetables = [];

function routeKey(a, b) {
  return a < b ? `${a}-${b}` : `${b}-${a}`;
}

function upsertRoute(spec) {
  const existing = routes.get(spec.id);
  if (!existing) {
    routes.set(spec.id, spec);
    return spec;
  }
  // Prefer the sequence with more resolved intermediate stops.
  if (spec.stops.length > existing.stops.length) {
    existing.stops = spec.stops;
    existing.distance_km = spec.distance_km;
  }
  existing.bus_types = [...new Set([...existing.bus_types, ...spec.bus_types])];
  return existing;
}

// 1 — curated intercity corridors.
let curatedCount = 0;
for (const [originId, destId, km, busTypes, viaNames] of ROUTES) {
  if (!stops.has(originId) || !stops.has(destId)) continue;

  const origin = stops.get(originId);
  const dest = stops.get(destId);
  const id = routeKey(originId, destId);

  const built = buildStopSequence(
    originId, destId, viaNames, km, `${origin.city}–${dest.city}`);
  if (!built) continue;

  const classes = [...new Set(busTypes.map(canonicalClass))];

  upsertRoute({
    id,
    name: `${origin.city} – ${dest.city}`,
    operator: 'MSRTC',
    corridor: true,
    origin_stop_id: originId,
    destination_stop_id: destId,
    origin_city: origin.city,
    destination_city: dest.city,
    distance_km: built.distanceKm,
    bus_types: classes,
    stops: built.stops,
  });
  curatedCount++;

  for (const cls of classes) {
    services.push({
      id: `${id}::${cls.replace(/\s+/g, '_')}`,
      route_id: id,
      bus_type: cls,
      source: 'corridor',
      departures: generateDepartures(built.distanceKm, cls, hashSeed(id + cls)),
    });
  }
}

// 2 — scraped depot timetables.
const rawTimetables = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'master_timetables.json'), 'utf8')
);

const stats = {
  timetableRows: rawTimetables.length,
  unknownSlug: 0,
  noTimes: 0,
  unresolvedDestination: 0,
  rejectedGeometry: 0,
  distanceCorrected: 0,
  scheduledServices: 0,
  syntheticRoutes: 0,
};
const unresolved = new Map();
const rejected = [];

// ── Geometric validation of a scraped origin/destination pair ────────────────
// A printed board distance is only usable if it is consistent with where the two
// stands actually are. Road distance can never be *less* than the great-circle
// distance, so a printed value below it is either a rounding artefact or, worse,
// proof that the destination name resolved to the wrong stand.
//
// Two failures this catches in the real scrape:
//   - Sinnar's board lists "AKOLA" at 42 km. That is Akole village (37 km),
//     not Akola city (328 km). Without this check the graph gains a 42 km edge
//     across a 328 km gap.
//   - Malegaon's board lists Shirdi at 915 km. Shirdi is 88 km away.
//
// Returns `{ km }` to use, or `{ reject: reason }`.
const MIN_RATIO_TRUST = 1.05;  // below this the printed value is imprecise
const MIN_RATIO_ACCEPT = 0.75; // below this the resolution itself is suspect
const MAX_RATIO_ACCEPT = 3.0;  // above this the printed value is a scrape error
const DETOUR_FACTOR = 1.15;    // road-vs-straight allowance when substituting
const ABS_SLACK_KM = 3;        // absolute rounding slack, for short hops

function validatePairDistance(originStop, destStop, printedKm) {
  const straight = haversineKm(originStop, destStop);
  if (straight < 0.5) return { reject: 'endpoints are effectively the same place' };

  if (printedKm == null) {
    return { km: round1(straight * 1.25) };
  }

  const ratio = printedKm / straight;

  if (ratio > MAX_RATIO_ACCEPT) {
    return {
      reject: `printed ${printedKm} km is ${ratio.toFixed(1)}x the ` +
        `${straight.toFixed(0)} km straight line`,
    };
  }
  // Absolute slack absorbs board rounding on short hops without weakening the
  // ratio test on long ones.
  if (printedKm < straight * MIN_RATIO_ACCEPT - ABS_SLACK_KM) {
    return {
      reject: `printed ${printedKm} km is only ${(ratio * 100).toFixed(0)}% of ` +
        `the ${straight.toFixed(0)} km straight line — destination likely ` +
        `resolved to the wrong stand`,
    };
  }
  if (ratio < MIN_RATIO_TRUST) {
    // Imprecise board rounding: substitute a geometrically sound distance.
    return { km: round1(straight * DETOUR_FACTOR), corrected: true };
  }
  return { km: round1(printedKm) };
}

for (const row of rawTimetables) {
  const origin = DEPOT_ORIGINS[row.origin_slug];
  if (origin === undefined) {
    stats.unknownSlug++;
    continue;
  }
  if (origin === null) continue; // deliberately dropped slug

  const minutes = [...new Set((row.times || []).flatMap(parseTimes))].sort((a, b) => a - b);
  if (minutes.length === 0) {
    stats.noTimes++;
    continue;
  }

  const { destination, via } = splitVia(row.destination || '');
  const busType = normaliseBusType(row.bus_type);
  const km = parseKm(row.distance_km);

  // Every row is retained for the Timetables screen, resolvable or not — a
  // departure board is useful even when the destination has no stand record.
  const destId = resolveStopId(destination);
  timetables.push({
    origin_stop_id: origin.id,
    origin_city: origin.city,
    destination: titleCase(destination),
    destination_stop_id: destId || null,
    via: via.map(titleCase),
    bus_type: busType,
    distance_km: km != null ? round1(km) : null,
    departures: minutes,
  });

  if (!destId || destId === origin.id) {
    if (!destId) {
      stats.unresolvedDestination++;
      const key = titleCase(destination);
      unresolved.set(key, (unresolved.get(key) || 0) + 1);
    }
    continue;
  }

  const originStop = stops.get(origin.id);
  const destStop = stops.get(destId);
  if (!originStop || !destStop) continue;

  const verdict = validatePairDistance(originStop, destStop, km);
  if (verdict.reject) {
    // Keep the departure board row (already pushed) but do not pollute the
    // graph with an edge we cannot trust.
    stats.rejectedGeometry++;
    rejected.push(`${origin.city} → ${titleCase(destination)}: ${verdict.reject}`);
    // Also drop the resolution from the retained row, so the app does not offer
    // a "plan this journey" action against a stand we just rejected.
    timetables[timetables.length - 1].destination_stop_id = null;
    continue;
  }
  if (verdict.corrected) stats.distanceCorrected++;

  // A resolvable pair with a trustworthy distance becomes a graph edge with a
  // real schedule — this is what lets the planner return actual departure times.
  const effectiveKm = verdict.km;

  const id = routeKey(origin.id, destId);
  const built = buildStopSequence(
    origin.id, destId, via, effectiveKm,
    `${origin.city}–${destStop.city} (board)`);
  if (!built) continue;

  const before = routes.has(id);
  upsertRoute({
    id,
    name: `${origin.city} – ${destStop.city}`,
    operator: 'MSRTC',
    corridor: false,
    origin_stop_id: origin.id,
    destination_stop_id: destId,
    origin_city: origin.city,
    destination_city: destStop.city,
    distance_km: built.distanceKm,
    bus_types: [busType],
    stops: built.stops,
  });
  if (!before) stats.syntheticRoutes++;

  services.push({
    id: `${id}::${busType.replace(/\s+/g, '_')}::${origin.id}::${services.length}`,
    route_id: id,
    bus_type: busType,
    source: 'timetable',
    from_stop_id: origin.id, // scraped boards are directional
    departures: minutes,
  });
  stats.scheduledServices++;
}

// ── Return workings for directional depot boards ─────────────────────────────
// A scraped board is one-directional: Akole's board lists departures *from*
// Akole. Taken literally that makes Akole unreachable — nothing ever runs into
// it — which is wrong. MSRTC buses work round trips: the vehicle that runs
// Akole→Pune in the morning runs Pune→Akole in the afternoon.
//
// So for every directional service a return working is generated, departing the
// far terminus after the outbound running time plus a layover. Estimated
// running time uses the same speed model as the Dart `EtaEngine` so outbound and
// return schedules stay mutually consistent.
const LAYOVER_MINUTES = 45;

function estimateRunMinutes(km, classKey) {
  const cls = SERVICE_CLASSES.find((c) => c.key === classKey) || SERVICE_CLASSES[0];
  // Mirrors EtaEngine.lengthFactor: short trips never reach cruise speed.
  const lengthFactor = 0.62 + 0.38 * (km / (km + 85));
  const kmph = Math.max(18, cls.cruiseKmph * lengthFactor);
  const running = (km / kmph) * 60;
  const breaks = Math.floor(running / 210) * 20;
  return Math.round(running + breaks);
}

const returnServices = [];
for (const svc of services) {
  if (svc.source !== 'timetable' || !svc.from_stop_id) continue;
  const route = routes.get(svc.route_id);
  if (!route) continue;

  const farTerminus =
    route.origin_stop_id === svc.from_stop_id
      ? route.destination_stop_id
      : route.origin_stop_id;
  if (farTerminus === svc.from_stop_id) continue;

  const runMinutes = estimateRunMinutes(route.distance_km, svc.bus_type);
  const turnaround = runMinutes + LAYOVER_MINUTES;

  returnServices.push({
    id: `${svc.route_id}::${svc.bus_type.replace(/\s+/g, '_')}::${farTerminus}::return${returnServices.length}`,
    route_id: svc.route_id,
    bus_type: svc.bus_type,
    source: 'return',
    from_stop_id: farTerminus,
    departures: svc.departures.map((m) => (m + turnaround) % 1440),
  });
}
services.push(...returnServices);
stats.returnServices = returnServices.length;

// ── Merge duplicate services on the same (route, class, direction) ───────────
const merged = new Map();
for (const svc of services) {
  const key = `${svc.route_id}|${svc.bus_type}|${svc.from_stop_id || ''}`;
  const existing = merged.get(key);
  if (!existing) {
    merged.set(key, { ...svc, departures: [...svc.departures] });
    continue;
  }
  existing.departures = [...new Set([...existing.departures, ...svc.departures])].sort((a, b) => a - b);
  // A published board is the most authoritative source; a modelled return
  // working is the least. Preserve the strongest provenance.
  const rank = { timetable: 3, return: 2, corridor: 1 };
  if ((rank[svc.source] || 0) > (rank[existing.source] || 0)) {
    existing.source = svc.source;
  }
}
const finalServices = [...merged.values()].map((s, i) => ({
  id: `svc-${i}`,
  route_id: s.route_id,
  bus_type: s.bus_type,
  source: s.source,
  from_stop_id: s.from_stop_id || null,
  departures: s.departures,
}));

// ── Prune orphan stops ───────────────────────────────────────────────────────
// A stop nobody can reach is noise on the map and in search results.
const usedStopIds = new Set();
for (const route of routes.values()) {
  for (const s of route.stops) usedStopIds.add(s.stop_id);
}
for (const t of timetables) {
  usedStopIds.add(t.origin_stop_id);
  if (t.destination_stop_id) usedStopIds.add(t.destination_stop_id);
}
const finalStops = [...stops.values()]
  .filter((s) => usedStopIds.has(s.id))
  .sort((a, b) => a.city.localeCompare(b.city) || a.name.localeCompare(b.name));

const finalRoutes = [...routes.values()].sort((a, b) => a.id.localeCompare(b.id));

// ── Final validation ─────────────────────────────────────────────────────────
// Every invariant the Dart engines and the app UI rely on is asserted here, at
// build time, so a bad dataset never ships. A violation is a hard failure: a
// silently wrong distance becomes a silently wrong fare and a silently wrong
// ETA, which is worse than no data at all.
const errors = [];

for (const route of finalRoutes) {
  const seq = route.stops;
  if (seq.length < 2) {
    errors.push(`${route.id}: only ${seq.length} stop(s)`);
    continue;
  }
  if (seq[0].cum_km !== 0) {
    errors.push(`${route.id}: first stop cum_km is ${seq[0].cum_km}, not 0`);
  }
  if (Math.abs(seq[seq.length - 1].cum_km - route.distance_km) > 0.15) {
    errors.push(
      `${route.id}: terminal cum_km ${seq[seq.length - 1].cum_km} != ` +
      `distance_km ${route.distance_km}`);
  }
  if (seq[0].stop_id !== route.origin_stop_id ||
      seq[seq.length - 1].stop_id !== route.destination_stop_id) {
    errors.push(`${route.id}: terminus stop ids do not match the sequence`);
  }

  const seen = new Set();
  for (let i = 0; i < seq.length; i++) {
    if (seq[i].seq !== i + 1) {
      errors.push(`${route.id}: sequence not contiguous at index ${i}`);
    }
    if (seen.has(seq[i].stop_id)) {
      errors.push(`${route.id}: repeats stop ${seq[i].stop_id}`);
    }
    seen.add(seq[i].stop_id);

    if (i === 0) continue;
    const along = seq[i].cum_km - seq[i - 1].cum_km;
    if (along <= 0) {
      errors.push(
        `${route.id}: cum_km not increasing at ${seq[i].stop_id} ` +
        `(${seq[i - 1].cum_km} -> ${seq[i].cum_km})`);
    }
    const straight = haversineKm(seq[i - 1], seq[i]);
    if (straight > 0.5 && along < straight) {
      errors.push(
        `${route.id}: ${along.toFixed(1)} km along but ` +
        `${straight.toFixed(1)} km straight between ` +
        `${seq[i - 1].stop_id} and ${seq[i].stop_id}`);
    }
  }

  for (const type of route.bus_types) {
    if (!CLASS_KEYS.has(type)) {
      errors.push(`${route.id}: unknown bus type "${type}"`);
    }
  }
}

const stopIdSet = new Set(finalStops.map((s) => s.id));
for (const route of finalRoutes) {
  for (const s of route.stops) {
    if (!stopIdSet.has(s.stop_id)) {
      errors.push(`${route.id}: references pruned stop ${s.stop_id}`);
    }
  }
}
const routeIdSet = new Set(finalRoutes.map((r) => r.id));
for (const svc of finalServices) {
  if (!routeIdSet.has(svc.route_id)) {
    errors.push(`service ${svc.id}: unknown route ${svc.route_id}`);
  }
  if (svc.departures.length === 0) {
    errors.push(`service ${svc.id}: no departures`);
  }
  for (const m of svc.departures) {
    if (!Number.isInteger(m) || m < 0 || m > 1439) {
      errors.push(`service ${svc.id}: invalid departure minute ${m}`);
    }
  }
  if (svc.from_stop_id) {
    const route = routes.get(svc.route_id);
    if (route && !route.stops.some((s) => s.stop_id === svc.from_stop_id)) {
      errors.push(
        `service ${svc.id}: departs ${svc.from_stop_id}, not on its route`);
    }
  }
}
for (const t of timetables) {
  if (!stopIdSet.has(t.origin_stop_id)) {
    errors.push(`timetable row from pruned stop ${t.origin_stop_id}`);
  }
  if (t.destination_stop_id && !stopIdSet.has(t.destination_stop_id)) {
    errors.push(`timetable row targets pruned stop ${t.destination_stop_id}`);
  }
}

// Connectivity: a stop nobody can reach is a dead search result.
const adjacency = new Map(finalStops.map((s) => [s.id, new Set()]));
for (const route of finalRoutes) {
  const ids = route.stops.map((s) => s.stop_id);
  for (const a of ids) {
    for (const b of ids) {
      if (a !== b) adjacency.get(a)?.add(b);
    }
  }
}
const visited = new Set([finalStops[0].id]);
const frontier = [finalStops[0].id];
while (frontier.length) {
  for (const next of adjacency.get(frontier.pop()) || []) {
    if (!visited.has(next)) {
      visited.add(next);
      frontier.push(next);
    }
  }
}
const isolated = finalStops.filter((s) => !visited.has(s.id));
if (isolated.length) {
  errors.push(`isolated stops: ${isolated.map((s) => s.id).join(', ')}`);
}

if (errors.length) {
  console.error(`\nDataset validation failed with ${errors.length} error(s):\n`);
  for (const error of errors.slice(0, 40)) console.error(`  - ${error}`);
  if (errors.length > 40) {
    console.error(`  ... and ${errors.length - 40} more`);
  }
  process.exit(1);
}

// ── Emit ─────────────────────────────────────────────────────────────────────
const bundle = {
  version: 3,
  generated_at: new Date().toISOString(),
  operator: 'MSRTC',
  source_note:
    'Stands and corridor distances from scripts/msrtc_data.js (official government road distances). ' +
    'Departure times from master_timetables.json (scraped MSRTC depot boards). ' +
    'Fares are computed at runtime by FareEngine from the stage tariff below.',
  fare_model: {
    stage_km: 6,
    round_to_nearest: 5,
    minimum_fare: 10,
    revision: '2026-07-18',
  },
  service_classes: SERVICE_CLASSES,
  stops: finalStops,
  routes: finalRoutes,
  services: finalServices,
  timetables,
};

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(bundle));

const bytes = fs.statSync(OUT).size;
const topUnresolved = [...unresolved.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12);

console.log('BussPass offline dataset built');
console.log(`  output              ${path.relative(ROOT, OUT)}  (${(bytes / 1024).toFixed(1)} KB)`);
console.log(`  stops               ${finalStops.length}`);
console.log(`  routes              ${finalRoutes.length}  (${curatedCount} curated corridors, ${stats.syntheticRoutes} from timetables)`);
console.log(`  services            ${finalServices.length}  (${stats.returnServices} modelled return workings)`);
console.log(`  departures          ${finalServices.reduce((n, s) => n + s.departures.length, 0)}`);
console.log(`  timetable rows      ${timetables.length} / ${stats.timetableRows} retained`);
console.log(`  dropped: unknown slug ${stats.unknownSlug}, no parsable time ${stats.noTimes}`);
console.log(`  destinations left unresolved (timetable-only): ${stats.unresolvedDestination}`);
if (topUnresolved.length) {
  console.log(`  most common unresolved: ${topUnresolved.map(([k, v]) => `${k}(${v})`).join(', ')}`);
}

console.log('\nData quality');
console.log(`  board distances substituted (imprecise):  ${stats.distanceCorrected}`);
console.log(`  pairs rejected on geometry:               ${stats.rejectedGeometry}`);
if (rejected.length) {
  for (const line of rejected.slice(0, 10)) console.log(`    · ${line}`);
  if (rejected.length > 10) {
    console.log(`    ... and ${rejected.length - 10} more`);
  }
}
console.log(`  corridor distances raised to geometric floor: ${geometryAdjustments.length}`);
for (const line of geometryAdjustments.slice(0, 10)) {
  console.log(`    · ${line}`);
}
if (geometryAdjustments.length > 10) {
  console.log(`    ... and ${geometryAdjustments.length - 10} more`);
}
console.log('\nAll invariants validated.');
