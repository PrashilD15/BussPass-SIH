// ─────────────────────────────────────────────────────────────────────────────
// MSRTC real data: bus stands + intercity route graph + fare model
// Based on:
//  - Real MSRTC bus stands (all 36 district HQ stands + major depot hubs +
//    tourist/pilgrimage stands) with GPS coordinates
//  - Real government road distances (NH/SH) between cities
//  - MSRTC official fare structure (18-Jul-2026 revision, per 6 km stage)
// ─────────────────────────────────────────────────────────────────────────────

// ── MSRTC Fare Model (per 6 km stage, 18-Jul-2026 revision) ─────────────────
// Source: MSRTC fare revision effective 18-Jul-2026 (STA approved 13.56% hike,
// reported by Free Press Journal / PTI / Mathrubhumi / Saptashwa).
//  - Ordinary (non-AC):               ₹11.40 / stage
//  - Semi Luxury (non-AC seater):     ₹13.65 / stage
//  - Ordinary Sleeper-Seater (non-AC):₹15.50 / stage
//  - Ordinary Sleeper (non-AC):       ₹16.75 / stage
//  - Shivshahi AC Seater:             ₹14.20 / stage
//  - Shivshahi AC Sleeper:            ₹15.35 / stage
//  - Shivneri AC Seater:              ₹21.25 / stage
//  - Shivneri AC Sleeper:             ₹25.35 / stage
// Fares rounded to nearest ₹5 (MSRTC policy). Stage = 6 km.

const FARE_STAGE_KM = 6; // one "stage" = 6 km (MSRTC convention)

const BUS_TYPES = {
  Ordinary:             { stageRate: 11.40, label: 'Ordinary' },
  'Semi Luxury':        { stageRate: 13.65, label: 'Semi Luxury' },
  Sleeper:              { stageRate: 16.75, label: 'Ordinary Sleeper' }, // alias for legacy routes
  'Sleeper Seater':     { stageRate: 15.50, label: 'Ordinary Sleeper-Seater' },
  'Ordinary Sleeper':   { stageRate: 16.75, label: 'Ordinary Sleeper' },
  Shivshahi:            { stageRate: 14.20, label: 'Shivshahi AC' },
  'Shivshahi Sleeper':  { stageRate: 15.35, label: 'Shivshahi AC Sleeper' },
  Shivneri:             { stageRate: 21.25, label: 'Shivneri AC' },
  'Shivneri Sleeper':   { stageRate: 25.35, label: 'Shivneri AC Sleeper' },
};

// Compute MSRTC fare for a distance in km for a given bus type (rounded to ₹5).
function computeFare(km, typeKey) {
  const t = BUS_TYPES[typeKey];
  if (!t) return 0;
  const stages = Math.ceil(km / FARE_STAGE_KM);
  const raw = stages * t.stageRate;
  return Math.max(10, Math.round(raw / 5) * 5);
}

// Interpolated duration estimate: ~40 km/h + fixed buffer for stops.
function durationHrs(km) {
  const hrs = km / 40 + 0.5;
  const lo = Math.floor(hrs);
  const hi = Math.ceil(hrs);
  return `${lo}-${hi} hrs`;
}

// ── Bus Stands ────────────────────────────────────────────────────────────────
// All 36 district HQ stands + major depot hubs + key tourist/pilgrimage stands.
// id, name, city, depot, lat, lng, region
const STANDS = [
  // ── Mumbai / Konkan Division ──
  { id: 'mumbai-dadar',    name: 'Dadar Bus Stand',           city: 'Mumbai',   depot: 'Dadar',           lat: 19.0178, lng: 72.8478 },
  { id: 'mumbai-central',  name: 'Mumbai Central ST Stand',   city: 'Mumbai',   depot: 'Mumbai Central',  lat: 18.9686, lng: 72.8194 },
  { id: 'mumbai-borivali', name: 'Borivali Bus Stand',        city: 'Mumbai',   depot: 'Borivali',        lat: 19.2345, lng: 72.8562 },
  { id: 'thane',           name: 'Thane Vandana ST Stand',    city: 'Thane',    depot: 'Thane Vandana',   lat: 19.1890, lng: 72.9781 },
  { id: 'palghar',         name: 'Palghar Bus Stand',         city: 'Palghar',  depot: 'Palghar',         lat: 19.6967, lng: 72.7655 },
  { id: 'raigad-alibag',   name: 'Alibag Bus Stand',          city: 'Alibag',   depot: 'Alibag',          lat: 18.6414, lng: 72.8721 },
  { id: 'panvel',          name: 'Panvel Bus Stand',          city: 'Panvel',   depot: 'Panvel',          lat: 18.9894, lng: 73.1175 },
  { id: 'ratnagiri',       name: 'Ratnagiri Bus Stand',       city: 'Ratnagiri',depot: 'Ratnagiri',       lat: 16.9944, lng: 73.3000 },
  { id: 'sindhudurg-oras', name: 'Oras (Sindhudurg) ST',      city: 'Oros',     depot: 'Sindhudurg',      lat: 16.0230, lng: 73.6170 },
  // ── Pune Division ──
  { id: 'pune-swargate',   name: 'Swargate Bus Stand',        city: 'Pune',     depot: 'Swargate',        lat: 18.5013, lng: 73.8567 },
  { id: 'pune-station',    name: 'Pune Station ST Stand',     city: 'Pune',     depot: 'Pune Station',    lat: 18.5284, lng: 73.8740 },
  { id: 'pune-shivajinagar',name: 'Shivajinagar Bus Stand',   city: 'Pune',     depot: 'Shivajinagar',    lat: 18.5308, lng: 73.8475 },
  { id: 'kolhapur',        name: 'Kolhapur Central ST Stand',city: 'Kolhapur', depot: 'Kolhapur',        lat: 16.7050, lng: 74.2433 },
  { id: 'sangli',          name: 'Sangli Bus Stand',          city: 'Sangli',   depot: 'Sangli',          lat: 16.8524, lng: 74.5815 },
  { id: 'satara',          name: 'Satara Bus Stand',          city: 'Satara',   depot: 'Satara',          lat: 17.6805, lng: 74.0183 },
  { id: 'solapur',         name: 'Solapur Bus Stand',         city: 'Solapur',  depot: 'Solapur',         lat: 17.6805, lng: 75.9064 },
  { id: 'ahmednagar',      name: 'Ahmednagar Bus Stand',      city: 'Ahmednagar',depot: 'Ahmednagar',      lat: 19.0948, lng: 74.7480 },
  // ── Nashik Division ──
  { id: 'nashik-cbs',      name: 'Nashik Central Bus Stand',  city: 'Nashik',   depot: 'Nashik CBS',      lat: 19.9975, lng: 73.7898 },
  { id: 'jalgaon',         name: 'Jalgaon Bus Stand',         city: 'Jalgaon',  depot: 'Jalgaon',         lat: 21.0077, lng: 75.5626 },
  { id: 'dhule',           name: 'Dhule Bus Stand',           city: 'Dhule',    depot: 'Dhule',           lat: 20.9042, lng: 74.7749 },
  { id: 'nandurbar',       name: 'Nandurbar Bus Stand',       city: 'Nandurbar',depot: 'Nandurbar',       lat: 21.3661, lng: 74.2370 },
  { id: 'shirdi',          name: 'Shirdi Bus Stand',          city: 'Shirdi',   depot: 'Shirdi',          lat: 19.7667, lng: 74.4764 },
  // ── Chhatrapati Sambhajinagar (Aurangabad) Division ──
  { id: 'csn',             name: 'CSN (Aurangabad) Bus Stand',city: 'Chhatrapati Sambhaji Nagar', depot: 'CSN', lat: 19.8762, lng: 75.3433 },
  { id: 'beed',            name: 'Beed Bus Stand',            city: 'Beed',     depot: 'Beed',            lat: 18.9892, lng: 75.7564 },
  { id: 'jalna',           name: 'Jalna Bus Stand',           city: 'Jalna',    depot: 'Jalna',           lat: 19.8392, lng: 75.8826 },
  { id: 'latur',           name: 'Latur Bus Stand',           city: 'Latur',    depot: 'Latur',           lat: 18.4088, lng: 76.5604 },
  { id: 'nanded',          name: 'Nanded Bus Stand',          city: 'Nanded',   depot: 'Nanded',          lat: 19.1383, lng: 77.3210 },
  { id: 'parbhani',        name: 'Parbhani Bus Stand',        city: 'Parbhani', depot: 'Parbhani',        lat: 19.2686, lng: 76.7708 },
  { id: 'hingoli',         name: 'Hingoli Bus Stand',         city: 'Hingoli',  depot: 'Hingoli',         lat: 19.7174, lng: 77.1473 },
  { id: 'dharashiv',       name: 'Dharashiv (Osmanabad) ST',  city: 'Dharashiv',depot: 'Dharashiv',       lat: 18.1520, lng: 76.0350 },
  // ── Nagpur Division ──
  { id: 'nagpur-ganeshpeth',name: 'Nagpur Ganeshpeth ST',     city: 'Nagpur',   depot: 'Ganeshpeth',      lat: 21.1458, lng: 79.0882 },
  { id: 'wardha',          name: 'Wardha Bus Stand',          city: 'Wardha',   depot: 'Wardha',          lat: 20.7453, lng: 78.6022 },
  { id: 'bhandara',        name: 'Bhandara Bus Stand',        city: 'Bhandara', depot: 'Bhandara',        lat: 21.1704, lng: 79.6481 },
  { id: 'chandrapur',      name: 'Chandrapur Bus Stand',      city: 'Chandrapur',depot:'Chandrapur',     lat: 19.9550, lng: 79.3000 },
  { id: 'gadchiroli',      name: 'Gadchiroli Bus Stand',      city: 'Gadchiroli',depot:'Gadchiroli',     lat: 20.1948, lng: 80.0034 },
  { id: 'gondia',          name: 'Gondia Bus Stand',          city: 'Gondia',   depot: 'Gondia',          lat: 21.4595, lng: 80.1936 },
  // ── Amravati Division ──
  { id: 'amravati',        name: 'Amravati Bus Stand',        city: 'Amravati', depot: 'Amravati',        lat: 20.9374, lng: 77.7796 },
  { id: 'akola',           name: 'Akola Bus Stand',           city: 'Akola',    depot: 'Akola',           lat: 20.7032, lng: 77.0061 },
  { id: 'buldhana',        name: 'Buldhana Bus Stand',        city: 'Buldhana', depot: 'Buldhana',        lat: 20.5294, lng: 76.1788 },
  { id: 'washim',          name: 'Washim Bus Stand',          city: 'Washim',   depot: 'Washim',          lat: 20.1016, lng: 77.1372 },
  { id: 'yavatmal',        name: 'Yavatmal Bus Stand',        city: 'Yavatmal', depot: 'Yavatmal',        lat: 20.3888, lng: 78.1202 },
  // ── Tourist / Pilgrimage / Connectivity hubs ──
  { id: 'lonavala',        name: 'Lonavala Bus Stand',        city: 'Lonavala', depot: 'Lonavala',        lat: 18.7481, lng: 73.4072 },
  { id: 'mahabaleshwar',   name: 'Mahabaleshwar Bus Stand',   city: 'Mahabaleshwar', depot: 'Mahabaleshwar', lat: 17.9244, lng: 73.6565 },
  { id: 'pandharpur',      name: 'Pandharpur Bus Stand',      city: 'Pandharpur',depot:'Pandharpur',     lat: 17.6786, lng: 75.3248 },
  { id: 'nashik-manmad',   name: 'Manmad Bus Stand',          city: 'Manmad',   depot: 'Manmad',          lat: 20.2708, lng: 74.4510 },
  // ── Mid-route / corridor stops where MSRTC buses actually stop ──────────
  // (Previously only resolvable as via-stop WAYPOINTS; added as full bus stands
  //  so "Locate Me" / nearest-stop snapping can resolve them too.)
  { id: 'sangamner',       name: 'Sangamner Bus Stand',       city: 'Sangamner', depot: 'Sangamner',      lat: 19.5648, lng: 74.2115 },
  { id: 'kasara',          name: 'Kasara Bus Stand',          city: 'Kasara',   depot: 'Kasara',          lat: 19.6436, lng: 73.4797 },
  { id: 'igatpuri',        name: 'Igatpuri Bus Stand',        city: 'Igatpuri', depot: 'Igatpuri',        lat: 19.6983, lng: 73.5556 },
  { id: 'agardanda',       name: 'Agardanda Jetty Bus Stop',  city: 'Agardanda',depot:'Agardanda',        lat: 18.5565, lng: 72.9186 },
  { id: 'kopargaon',       name: 'Kopargaon Bus Stand',       city: 'Kopargaon',depot:'Kopargaon',        lat: 19.8820, lng: 74.4764 },
  { id: 'indapur',         name: 'Indapur Bus Stand',         city: 'Indapur',  depot: 'Indapur',         lat: 18.1147, lng: 75.0282 },
  { id: 'wai',             name: 'Wai Bus Stand',             city: 'Wai',      depot: 'Wai',             lat: 17.9502, lng: 73.8957 },
  { id: 'malegaon',        name: 'Malegaon Bus Stand',        city: 'Malegaon', depot: 'Malegaon',        lat: 20.5523, lng: 74.5372 },
];

// ── Waypoint coordinates for via-stops NOT in STANDS ─────────────────────────
// These are real towns/cities along MSRTC intercity routes that sit between the
// origin/destination stands. Used to resolve via_stops (city names) to exact
// lat/lng so the map polyline follows the actual corridor instead of a straight
// line. Keys are lowercase city names as they appear in route.via_stops.
const WAYPOINTS = {
  'kasara':    { lat: 19.6436, lng: 73.4797 },
  'igatpuri':  { lat: 19.6983, lng: 73.5556 },
  'agardanda': { lat: 18.5565, lng: 72.9186 },
  'kopargaon': { lat: 19.8820, lng: 74.4764 },
  'sangamner': { lat: 19.5648, lng: 74.2115 },
  'indapur':   { lat: 18.1147, lng: 75.0282 },
  'wai':       { lat: 17.9502, lng: 73.8957 },
  'malegaon':  { lat: 20.5523, lng: 74.5372 },
  'khopoli':   { lat: 18.7866, lng: 73.3409 },
  'rajgurunagar': { lat: 18.8689, lng: 73.8840 },
};

// ── Intercity Routes (real gov distances in km) ─────────────────────────────
// Each: [originStopId, destinationStopId, distanceKm, [busTypes], [viaStops]]
// dist Href = government road distance; default bus types per route tier.
const ROUTES = [
  // Mumbai ⇄ Pune (via expressway / old highway)
  ['mumbai-dadar',    'pune-swargate',   150, ['Ordinary', 'Semi Luxury', 'Shivshahi', 'Shivneri'], ['Panvel', 'Lonavala']],
  ['mumbai-central',  'pune-station',    158, ['Ordinary', 'Semi Luxury', 'Shivshahi', 'Shivneri'], ['Panvel', 'Lonavala']],
  ['mumbai-borivali', 'pune-swargate',   148, ['Ordinary', 'Shivshahi', 'Shivneri'], ['Lonavala']],
  ['thane',           'pune-swargate',   145, ['Ordinary', 'Semi Luxury', 'Shivneri'], ['Lonavala']],
  // Mumbai ⇄ Nashik
  ['mumbai-central',  'nashik-cbs',      175, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Kasara', 'Igatpuri']],
  ['mumbai-borivali', 'nashik-cbs',      180, ['Ordinary', 'Semi Luxury'], ['Igatpuri']],
  // Mumbai ⇄ Kolhapur / Sangli / Satara (via Pune)
  ['mumbai-central',  'kolhapur',        376, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Pune', 'Satara', 'Sangli']],
  ['mumbai-central',  'sangli',          390, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Pune', 'Satara']],
  ['mumbai-central',  'satara',          265, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Pune']],
  // Mumbai ⇄ Konkan coast
  ['mumbai-central',  'raigad-alibag',   95, ['Ordinary', 'Semi Luxury', 'Shivneri'], ['Panvel']],
  ['mumbai-central',  'ratnagiri',       330, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Alibag', 'Agardanda']],
  ['mumbai-dadar',    'sindhudurg-oras', 480, ['Ordinary', 'Semi Luxury'], ['Ratnagiri']],
  ['mumbai-central',  'palghar',         105, ['Ordinary'], []],
  // Mumbai ⇄ Aurangabad (CSN)
  ['mumbai-central',  'csn',             400, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Nashik', 'Manmad']],
  // Mumbai ⇄ Shirdi
  ['mumbai-central',  'shirdi',          245, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Nashik', 'Kopargaon']],
  // Pune ⇄ Nashik
  ['pune-swargate',   'nashik-cbs',      212, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Sangamner']],
  ['pune-station',    'nashik-cbs',      212, ['Ordinary', 'Semi Luxury'], ['Sangamner']],
  // Sangamner ⇄ Pune (Shivajinagar) — direct service via Rajgurunagar
  ['sangamner',       'pune-shivajinagar', 150, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Rajgurunagar']],
  // Pune ⇄ Ahmednagar ⇄ Aurangabad
  ['pune-swargate',   'ahmednagar',      125, ['Ordinary', 'Semi Luxury', 'Shivshahi'], []],
  ['pune-swargate',   'csn',             235, ['Ordinary', 'Semi Luxury', 'Shivshahi', 'Shivneri'], ['Ahmednagar']],
  ['ahmednagar',      'csn',             120, ['Ordinary', 'Semi Luxury'], []],
  // Pune ⇄ Solapur / Kolhapur / Satara
  ['pune-swargate',   'solapur',         250, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Indapur']],
  ['pune-swargate',   'kolhapur',        240, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Satara']],
  ['pune-swargate',   'sangli',          230, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Satara']],
  ['pune-swargate',   'satara',          118, ['Ordinary', 'Semi Luxury'], []],
  ['pune-swargate',   'mahabaleshwar',   120, ['Ordinary', 'Semi Luxury', 'Shivneri'], ['Wai']],
  ['pune-swargate',   'pandharpur',      210, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Baramati', 'Indapur']],
  // Nashik ⇄ Shirdi / Dhule / Jalgaon
  ['nashik-cbs',      'shirdi',          90,  ['Ordinary', 'Semi Luxury'], ['Kopargaon']],
  ['nashik-cbs',      'dhule',           155, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Malegaon']],
  ['nashik-cbs',      'nandurbar',       230, ['Ordinary', 'Semi Luxury'], ['Dhule']],
  ['nashik-cbs',      'jalgaon',         255, ['Ordinary', 'Semi Luxury', 'Shivshahi'], []],
  ['jalgaon',         'dhule',           100,  ['Ordinary', 'Semi Luxury'], []],
  ['jalgaon',         'pune-swargate',   425, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Chhatrapati Sambhaji Nagar', 'Ahmednagar']],
  ['dhule',           'nandurbar',       110, ['Ordinary'], []],
  // Aurangabad-centric
  ['csn',             'jalna',           65,  ['Ordinary', 'Semi Luxury'], []],
  ['csn',             'beed',            125, ['Ordinary', 'Semi Luxury'], []],
  ['csn',             'parbhani',        180, ['Ordinary', 'Semi Luxury'], ['Jalna']],
  ['csn',             'nanded',          230, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Parbhani']],
  ['csn',             'latur',           240, ['Ordinary', 'Semi Luxury'], []],
  ['csn',             'dharashiv',       240, ['Ordinary', 'Semi Luxury'], ['Beed']],
  ['csn',             'hingoli',         240, ['Ordinary', 'Semi Luxury'], ['Jalna', 'Parbhani']],
  ['nanded',          'latur',           130, ['Ordinary', 'Semi Luxury'], []],
  ['nanded',          'hingoli',         90,  ['Ordinary'], []],
  ['latur',           'dharashiv',       70,  ['Ordinary'], []],
  ['parbhani',        'hingoli',         70,  ['Ordinary'], []],
  ['beed',            'dharashiv',       110,  ['Ordinary'], []],
  ['pune-swargate',   'latur',           350, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Solapur']],
  ['pune-swargate',   'nanded',          500, ['Ordinary', 'Semi Luxury'], ['Ahmednagar', 'Latur']],
  ['solapur',         'pandharpur',      145, ['Ordinary', 'Semi Luxury'], []],
  ['solapur',         'latur',           120, ['Ordinary', 'Semi Luxury'], []],
  // Nagpur-centric
  ['nagpur-ganeshpeth', 'wardha',        78,  ['Ordinary', 'Semi Luxury'], []],
  ['nagpur-ganeshpeth', 'amravati',      156, ['Ordinary', 'Semi Luxury', 'Shivshahi'], []],
  ['nagpur-ganeshpeth', 'bhandara',      62,  ['Ordinary'], []],
  ['nagpur-ganeshpeth', 'chandrapur',    148, ['Ordinary', 'Semi Luxury'], []],
  ['nagpur-ganeshpeth', 'gondia',        145, ['Ordinary', 'Semi Luxury'], ['Bhandara']],
  ['nagpur-ganeshpeth', 'gadchiroli',    180, ['Ordinary'], []],
  // Amravati-centric
  ['amravati',        'akola',           90,  ['Ordinary', 'Semi Luxury'], []],
  ['amravati',        'washim',          120, ['Ordinary'], []],
  ['amravati',        'yavatmal',        90,  ['Ordinary', 'Semi Luxury'], []],
  ['akola',           'washim',          80,  ['Ordinary'], []],
  ['akola',           'buldhana',        105,  ['Ordinary'], []],
  ['buldhana',        'jalgaon',         110, ['Ordinary', 'Semi Luxury'], []],
  ['yavatmal',        'wardha',          90,  ['Ordinary'], []],
  ['yavatmal',        'nanded',          205, ['Ordinary', 'Semi Luxury'], ['Hingoli']],
  // Long-haul spine routes
  ['nagpur-ganeshpeth', 'pune-swargate', 700, ['Ordinary', 'Semi Luxury', 'Shivshahi', 'Sleeper'], ['Amravati', 'Ahmednagar']],
  ['nagpur-ganeshpeth', 'solapur',       610, ['Ordinary', 'Semi Luxury'], ['Amravati', 'Akola']],
  ['mumbai-central',  'nagpur-ganeshpeth', 840, ['Ordinary', 'Sleeper', 'Shivshahi'], ['Nashik', 'Akola', 'Amravati']],
  ['mumbai-central',  'amravati',        690, ['Ordinary', 'Sleeper', 'Shivshahi'], ['Nashik', 'Akola']],
  ['pune-swargate',   'amravati',        560, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Ahmednagar', 'Jalgaon']],
  ['pune-swargate',   'akola',           500, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Ahmednagar', 'Jalgaon']],
  ['jalgaon',         'csn',             260, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['Manmad']],
  ['jalgaon',         'amravati',        265,  ['Ordinary', 'Semi Luxury'], ['Akola']],
  ['washim',          'nanded',          210, ['Ordinary'], ['Parbhani']],
];

// ── Export ────────────────────────────────────────────────────────────────────
module.exports = { BUS_TYPES, computeFare, durationHrs, STANDS, WAYPOINTS, ROUTES };
