// ─────────────────────────────────────────────────────────────────────────────
// Depot origin resolution for scraped MSRTC timetables.
//
// `master_timetables.json` identifies each timetable block by an `origin_slug`
// taken from the source page URL. Those slugs are not stable identifiers — some
// carry marketing suffixes ("-msrtc", "-bus-timings"), some are duplicated
// ("nashik-1-msrtc" / "nashik-2" are two stands in the same city), and one is a
// scraped article rather than a depot.
//
// This table resolves every slug to a real MSRTC stand with coordinates so the
// timetables can be joined onto the stop graph. Slugs mapped to `null` are
// deliberately dropped.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @type {Record<string, {id: string, name: string, city: string, depot: string,
 *                        lat: number, lng: number, district: string} | null>}
 */
const DEPOT_ORIGINS = {
  // NOTE: "akola-msrtc" in the source data is Akole (Ahmednagar district), not
  // Akola city — its timetable is dominated by short hops to Rajur (20 km),
  // Sangamner and Ganore, which are all Akole-taluka villages.
  'akola-msrtc': {
    id: 'akole', name: 'Akole Bus Stand', city: 'Akole', depot: 'Akole',
    lat: 19.5340, lng: 73.9328, district: 'Ahmednagar',
  },
  'igatpuri': {
    id: 'igatpuri', name: 'Igatpuri Bus Stand', city: 'Igatpuri', depot: 'Igatpuri',
    lat: 19.6983, lng: 73.5556, district: 'Nashik',
  },
  'jamkhed': {
    id: 'jamkhed', name: 'Jamkhed Bus Stand', city: 'Jamkhed', depot: 'Jamkhed',
    lat: 18.6469, lng: 75.3167, district: 'Ahmednagar',
  },
  'kalwan': {
    id: 'kalwan', name: 'Kalwan Bus Stand', city: 'Kalwan', depot: 'Kalwan',
    lat: 20.4900, lng: 74.0100, district: 'Nashik',
  },
  'kopargaon': {
    id: 'kopargaon', name: 'Kopargaon Bus Stand', city: 'Kopargaon', depot: 'Kopargaon',
    lat: 19.8820, lng: 74.4764, district: 'Ahmednagar',
  },
  'lasalgaon': {
    id: 'lasalgaon', name: 'Lasalgaon Bus Stand', city: 'Lasalgaon', depot: 'Lasalgaon',
    lat: 20.1450, lng: 74.2400, district: 'Nashik',
  },
  'malegaon': {
    id: 'malegaon', name: 'Malegaon Bus Stand', city: 'Malegaon', depot: 'Malegaon',
    lat: 20.5523, lng: 74.5372, district: 'Nashik',
  },
  'manmad': {
    id: 'nashik-manmad', name: 'Manmad Bus Stand', city: 'Manmad', depot: 'Manmad',
    lat: 20.2708, lng: 74.4510, district: 'Nashik',
  },
  'nandgaon': {
    id: 'nandgaon', name: 'Nandgaon Bus Stand', city: 'Nandgaon', depot: 'Nandgaon',
    lat: 20.3072, lng: 74.6572, district: 'Nashik',
  },
  // Both Nashik slugs resolve to the same city; CBS is the intercity stand.
  'nashik-1-msrtc': {
    id: 'nashik-cbs', name: 'Nashik Central Bus Stand', city: 'Nashik', depot: 'Nashik CBS',
    lat: 19.9975, lng: 73.7898, district: 'Nashik',
  },
  'nashik-2': {
    id: 'nashik-cbs', name: 'Nashik Central Bus Stand', city: 'Nashik', depot: 'Nashik CBS',
    lat: 19.9975, lng: 73.7898, district: 'Nashik',
  },
  'newasa': {
    id: 'nevasa', name: 'Nevasa Bus Stand', city: 'Nevasa', depot: 'Nevasa',
    lat: 19.5400, lng: 74.9300, district: 'Ahmednagar',
  },
  'parner': {
    id: 'parner', name: 'Parner Bus Stand', city: 'Parner', depot: 'Parner',
    lat: 19.0022, lng: 74.4386, district: 'Ahmednagar',
  },
  'pathardi': {
    id: 'pathardi', name: 'Pathardi Bus Stand', city: 'Pathardi', depot: 'Pathardi',
    lat: 19.1725, lng: 75.1783, district: 'Ahmednagar',
  },
  // Scraped help article, not a depot.
  'pet-how-to-book-msrtc-bus-ticket-online': null,
  'pimpalgaon': {
    id: 'pimpalgaon-baswant', name: 'Pimpalgaon Baswant Bus Stand',
    city: 'Pimpalgaon Baswant', depot: 'Pimpalgaon',
    lat: 20.1700, lng: 73.9800, district: 'Nashik',
  },
  'sangamner': {
    id: 'sangamner', name: 'Sangamner Bus Stand', city: 'Sangamner', depot: 'Sangamner',
    lat: 19.5648, lng: 74.2115, district: 'Ahmednagar',
  },
  'satana': {
    id: 'satana', name: 'Satana (Baglan) Bus Stand', city: 'Satana', depot: 'Satana',
    lat: 20.6000, lng: 74.2000, district: 'Nashik',
  },
  'shevgaon': {
    id: 'shevgaon', name: 'Shevgaon Bus Stand', city: 'Shevgaon', depot: 'Shevgaon',
    lat: 19.3500, lng: 75.2300, district: 'Ahmednagar',
  },
  'shirdi': {
    id: 'shirdi', name: 'Shirdi Bus Stand', city: 'Shirdi', depot: 'Shirdi',
    lat: 19.7667, lng: 74.4764, district: 'Ahmednagar',
  },
  'shrigonda': {
    id: 'shrigonda', name: 'Shrigonda Bus Stand', city: 'Shrigonda', depot: 'Shrigonda',
    lat: 18.6167, lng: 74.7000, district: 'Ahmednagar',
  },
  'shrirampur': {
    id: 'shrirampur', name: 'Shrirampur Bus Stand', city: 'Shrirampur', depot: 'Shrirampur',
    lat: 19.6200, lng: 74.6600, district: 'Ahmednagar',
  },
  'sinnar': {
    id: 'sinnar', name: 'Sinnar Bus Stand', city: 'Sinnar', depot: 'Sinnar',
    lat: 19.8500, lng: 74.0000, district: 'Nashik',
  },
  'tarakpur': {
    id: 'ahmednagar', name: 'Ahmednagar Bus Stand', city: 'Ahmednagar', depot: 'Tarakpur',
    lat: 19.0948, lng: 74.7480, district: 'Ahmednagar',
  },
  'yeola-msrtc-bus-timings': {
    id: 'yeola', name: 'Yeola Bus Stand', city: 'Yeola', depot: 'Yeola',
    lat: 20.0428, lng: 74.4897, district: 'Nashik',
  },
};

// ── Bus type normalisation for scraped labels ────────────────────────────────
// The scrape produced 19 distinct strings for 8 real service classes, including
// typos ("Lalapri", "Lalpariz", "Lalpari`"), a stray column header
// ("Kilometre"), and ambiguous either/or labels. Everything is folded onto the
// canonical MSRTC service keys used by the fare model.
const BUS_TYPE_ALIASES = {
  'ordinary': 'Ordinary',
  'lalpari': 'Ordinary',
  'lalapri': 'Ordinary',
  'lalpariz': 'Ordinary',
  'lalpari`': 'Ordinary',
  'k lalpari': 'Ordinary',
  'lalpari ( long route bus )': 'Ordinary',
  'e-bus': 'Ordinary',
  'shatal': 'Ordinary',
  'kilometre': 'Ordinary',
  'ashiad': 'Semi Luxury',
  'semi luxury or ashiad': 'Semi Luxury',
  'semi luxury or ashid': 'Semi Luxury',
  'hirkani': 'Semi Luxury',
  'shivshahi': 'Shivshahi',
  'not fixed ( shivshahi or lalpari )': 'Shivshahi',
  'e-shivneri': 'Shivneri',
  'shivneri': 'Shivneri',
  'sleeper': 'Ordinary Sleeper',
  'shayanyan': 'Ordinary Sleeper',
  'shayanyan bus': 'Ordinary Sleeper',
};

function normaliseBusType(raw) {
  if (!raw) return 'Ordinary';
  const key = String(raw).trim().toLowerCase().replace(/\s+/g, ' ');
  return BUS_TYPE_ALIASES[key] || 'Ordinary';
}

module.exports = { DEPOT_ORIGINS, BUS_TYPE_ALIASES, normaliseBusType };
