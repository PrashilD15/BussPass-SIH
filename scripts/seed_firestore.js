// ─────────────────────────────────────────────────────────────────────────────
// India State Transport (STC) Firestore Seed Script
// Run with: node scripts/seed_firestore.js
// Requires: npm install firebase-admin
// ─────────────────────────────────────────────────────────────────────────────
// USAGE:
//  1. Download your Firebase service account key from:
//     Firebase Console → Project Settings → Service Accounts → Generate new private key
//  2. Save it as scripts/serviceAccountKey.json
//  3. Run: npm install firebase-admin && node scripts/seed_firestore.js
// ─────────────────────────────────────────────────────────────────────────────

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
});

const db = getFirestore();

// ── Bus Stops ─────────────────────────────────────────────────────────────────
const busStops = [
  // Mumbai
  { id: 'mumbai-dadar',     name: 'Dadar Bus Stand',         city: 'Mumbai',   depot: 'Dadar',           lat: 19.0178, lng: 72.8478 },
  { id: 'mumbai-central',   name: 'Mumbai Central ST Stand', city: 'Mumbai',   depot: 'Mumbai Central',  lat: 18.9686, lng: 72.8194 },
  { id: 'mumbai-borivali',  name: 'Borivali Bus Stand',      city: 'Mumbai',   depot: 'Borivali',        lat: 19.2345, lng: 72.8562 },
  { id: 'mumbai-thane',     name: 'Thane Vandana ST Stand',  city: 'Thane',    depot: 'Thane Vandana',   lat: 19.1890, lng: 72.9781 },
  // Pune
  { id: 'pune-swargate',    name: 'Swargate Bus Stand',      city: 'Pune',     depot: 'Swargate',        lat: 18.5013, lng: 73.8567 },
  { id: 'pune-station',     name: 'Pune Station ST Stand',   city: 'Pune',     depot: 'Pune Station',    lat: 18.5284, lng: 73.8740 },
  { id: 'pune-shivajinagar',name: 'Shivajinagar Bus Stand',  city: 'Pune',     depot: 'Shivajinagar',    lat: 18.5308, lng: 73.8475 },
  { id: 'pune-wakad',       name: 'Wakad Bus Stop',          city: 'Pune',     depot: 'Wakad',           lat: 18.5900, lng: 73.7600 },
  // Nashik
  { id: 'nashik-cbs',       name: 'Nashik CBS Bus Stand',    city: 'Nashik',   depot: 'Nashik CBS',      lat: 19.9975, lng: 73.7898 },
  { id: 'nashik-municipal', name: 'Nashik Municipal Stand',  city: 'Nashik',   depot: 'Nashik Municipal',lat: 19.9976, lng: 73.7901 },
  // Kolhapur
  { id: 'kolhapur-central', name: 'Kolhapur Central ST',     city: 'Kolhapur', depot: 'Kolhapur',        lat: 16.7050, lng: 74.2433 },
  // Aurangabad / CSN
  { id: 'csn-central',      name: 'CSN Bus Stand',           city: 'Chhatrapati Sambhaji Nagar', depot: 'CSN', lat: 19.8762, lng: 75.3433 },
  // Solapur
  { id: 'solapur-central',  name: 'Solapur Bus Stand',       city: 'Solapur',  depot: 'Solapur',         lat: 17.6805, lng: 75.9064 },
  // Nagpur
  { id: 'nagpur-ganeshpeth',name: 'Nagpur Ganeshpeth ST',    city: 'Nagpur',   depot: 'Ganeshpeth',      lat: 21.1458, lng: 79.0882 },
  // Shirdi
  { id: 'shirdi-st',        name: 'Shirdi Bus Stand',        city: 'Shirdi',   depot: 'Shirdi',          lat: 19.7667, lng: 74.4764 },
  // Sangli
  { id: 'sangli-st',        name: 'Sangli Bus Stand',        city: 'Sangli',   depot: 'Sangli',          lat: 16.8524, lng: 74.5815 },
  // Satara
  { id: 'satara-st',        name: 'Satara Bus Stand',        city: 'Satara',   depot: 'Satara',          lat: 17.6805, lng: 74.0183 },
  // Ratnagiri
  { id: 'ratnagiri-st',     name: 'Ratnagiri Bus Stand',     city: 'Ratnagiri',depot: 'Ratnagiri',       lat: 16.9944, lng: 73.3000 },
  // Nanded
  { id: 'nanded-st',        name: 'Nanded Bus Stand',        city: 'Nanded',   depot: 'Nanded',          lat: 19.1383, lng: 77.3210 },
  // Jalgaon
  { id: 'jalgaon-st',       name: 'Jalgaon Bus Stand',       city: 'Jalgaon',  depot: 'Jalgaon',         lat: 21.0077, lng: 75.5626 },
  // Latur
  { id: 'latur-st',         name: 'Latur Bus Stand',         city: 'Latur',    depot: 'Latur',           lat: 18.4088, lng: 76.5604 },
  // Panvel
  { id: 'panvel-st',        name: 'Panvel Bus Stand',        city: 'Panvel',   depot: 'Panvel',          lat: 18.9894, lng: 73.1175 },
  // Lonavala
  { id: 'lonavala-st',      name: 'Lonavala Bus Stand',      city: 'Lonavala', depot: 'Lonavala',        lat: 18.7481, lng: 73.4072 },
  // Mahabaleshwar
  { id: 'mahabaleshwar-st', name: 'Mahabaleshwar Bus Stand', city: 'Mahabaleshwar', depot: 'Mahabaleshwar', lat: 17.9244, lng: 73.6565 },
];

// ── Routes ────────────────────────────────────────────────────────────────────
const routes = [
  {
    id: 'mumbai-pune-shivneri',
    name: 'Mumbai – Pune (Shivneri AC)',
    origin_stop_id: 'mumbai-dadar',
    destination_stop_id: 'pune-swargate',
    origin_city: 'Mumbai',
    destination_city: 'Pune',
    distance_km: 150,
    duration_hrs: '3-4 hrs',
    fare_min: 306,
    fare_max: 614,
    bus_types: ['Shivneri AC', 'Semi Luxury', 'Ordinary'],
    via_stops: ['Lonavala', 'Panvel'],
    first_bus: '05:00 AM',
    last_bus: '10:30 PM',
  },
  {
    id: 'pune-nashik',
    name: 'Pune – Nashik',
    origin_stop_id: 'pune-swargate',
    destination_stop_id: 'nashik-cbs',
    origin_city: 'Pune',
    destination_city: 'Nashik',
    distance_km: 212,
    duration_hrs: '4-5 hrs',
    fare_min: 230,
    fare_max: 440,
    bus_types: ['Shivshahi', 'Semi Luxury', 'Ordinary'],
    via_stops: ['Sinnar', 'Sangamner'],
    first_bus: '06:00 AM',
    last_bus: '09:00 PM',
  },
  {
    id: 'nashik-shirdi',
    name: 'Nashik – Shirdi',
    origin_stop_id: 'nashik-cbs',
    destination_stop_id: 'shirdi-st',
    origin_city: 'Nashik',
    destination_city: 'Shirdi',
    distance_km: 90,
    duration_hrs: '2-3 hrs',
    fare_min: 100,
    fare_max: 200,
    bus_types: ['Ordinary', 'Semi Luxury'],
    via_stops: ['Kopargaon'],
    first_bus: '05:30 AM',
    last_bus: '08:00 PM',
  },
  {
    id: 'mumbai-nashik',
    name: 'Mumbai – Nashik',
    origin_stop_id: 'mumbai-central',
    destination_stop_id: 'nashik-cbs',
    origin_city: 'Mumbai',
    destination_city: 'Nashik',
    distance_km: 165,
    duration_hrs: '3.5-5 hrs',
    fare_min: 220,
    fare_max: 420,
    bus_types: ['Shivshahi', 'Semi Luxury', 'Ordinary'],
    via_stops: ['Kasara', 'Igatpuri'],
    first_bus: '06:00 AM',
    last_bus: '11:00 PM',
  },
  {
    id: 'mumbai-kolhapur',
    name: 'Mumbai – Kolhapur',
    origin_stop_id: 'mumbai-central',
    destination_stop_id: 'kolhapur-central',
    origin_city: 'Mumbai',
    destination_city: 'Kolhapur',
    distance_km: 376,
    duration_hrs: '7-8 hrs',
    fare_min: 420,
    fare_max: 850,
    bus_types: ['Shivshahi', 'Semi Luxury', 'Ordinary'],
    via_stops: ['Pune', 'Satara', 'Sangli'],
    first_bus: '06:30 AM',
    last_bus: '10:30 PM',
  },
  {
    id: 'pune-solapur',
    name: 'Pune – Solapur',
    origin_stop_id: 'pune-swargate',
    destination_stop_id: 'solapur-central',
    origin_city: 'Pune',
    destination_city: 'Solapur',
    distance_km: 240,
    duration_hrs: '4-5 hrs',
    fare_min: 250,
    fare_max: 480,
    bus_types: ['Ordinary', 'Semi Luxury'],
    via_stops: ['Indapur', 'Barshi'],
    first_bus: '06:00 AM',
    last_bus: '10:00 PM',
  },
  {
    id: 'pune-csn',
    name: 'Pune – Chhatrapati Sambhaji Nagar',
    origin_stop_id: 'pune-swargate',
    destination_stop_id: 'csn-central',
    origin_city: 'Pune',
    destination_city: 'Chhatrapati Sambhaji Nagar',
    distance_km: 235,
    duration_hrs: '4-5 hrs',
    fare_min: 260,
    fare_max: 520,
    bus_types: ['Shivshahi', 'Ordinary'],
    via_stops: ['Ahmednagar'],
    first_bus: '05:30 AM',
    last_bus: '11:00 PM',
  },
  {
    id: 'mumbai-shirdi',
    name: 'Mumbai – Shirdi',
    origin_stop_id: 'mumbai-central',
    destination_stop_id: 'shirdi-st',
    origin_city: 'Mumbai',
    destination_city: 'Shirdi',
    distance_km: 250,
    duration_hrs: '5-6 hrs',
    fare_min: 280,
    fare_max: 560,
    bus_types: ['Shivshahi', 'Ordinary'],
    via_stops: ['Nashik', 'Kopargaon'],
    first_bus: '06:00 AM',
    last_bus: '09:00 PM',
  },
  {
    id: 'pune-kolhapur',
    name: 'Pune – Kolhapur',
    origin_stop_id: 'pune-swargate',
    destination_stop_id: 'kolhapur-central',
    origin_city: 'Pune',
    destination_city: 'Kolhapur',
    distance_km: 228,
    duration_hrs: '4-5 hrs',
    fare_min: 240,
    fare_max: 470,
    bus_types: ['Shivshahi', 'Ordinary', 'Semi Luxury'],
    via_stops: ['Satara', 'Sangli'],
    first_bus: '06:00 AM',
    last_bus: '10:30 PM',
  },
  {
    id: 'thane-pune',
    name: 'Thane – Pune',
    origin_stop_id: 'mumbai-thane',
    destination_stop_id: 'pune-swargate',
    origin_city: 'Thane',
    destination_city: 'Pune',
    distance_km: 145,
    duration_hrs: '3-4 hrs',
    fare_min: 290,
    fare_max: 580,
    bus_types: ['Shivneri AC', 'Ordinary'],
    via_stops: ['Lonavala'],
    first_bus: '06:00 AM',
    last_bus: '10:00 PM',
  },
  {
    id: 'nagpur-pune',
    name: 'Nagpur – Pune',
    origin_stop_id: 'nagpur-ganeshpeth',
    destination_stop_id: 'pune-swargate',
    origin_city: 'Nagpur',
    destination_city: 'Pune',
    distance_km: 700,
    duration_hrs: '12-14 hrs',
    fare_min: 700,
    fare_max: 1400,
    bus_types: ['Shivshahi', 'Sleeper'],
    via_stops: ['Wardha', 'Yavatmal', 'Latur'],
    first_bus: '05:00 PM',
    last_bus: '08:00 PM',
  },
  {
    id: 'jalgaon-pune',
    name: 'Jalgaon – Pune',
    origin_stop_id: 'jalgaon-st',
    destination_stop_id: 'pune-swargate',
    origin_city: 'Jalgaon',
    destination_city: 'Pune',
    distance_km: 348,
    duration_hrs: '6-8 hrs',
    fare_min: 380,
    fare_max: 760,
    bus_types: ['Ordinary', 'Semi Luxury'],
    via_stops: ['Dhule', 'Nashik'],
    first_bus: '05:30 AM',
    last_bus: '09:00 PM',
  },
];

// ── Seed Function ─────────────────────────────────────────────────────────────
async function seedData() {
  console.log('🚌 Starting India State Transport Firestore seed...\n');

  // Seed Bus Stops
  console.log(`📍 Seeding ${busStops.length} bus stops...`);
  const stopBatch = db.batch();
  for (const stop of busStops) {
    const { id, ...data } = stop;
    const ref = db.collection('bus_stops').doc(id);
    stopBatch.set(ref, data);
  }
  await stopBatch.commit();
  console.log('✅ Bus stops seeded!\n');

  // Seed Routes
  console.log(`🗺️  Seeding ${routes.length} routes...`);
  const routeBatch = db.batch();
  for (const route of routes) {
    const { id, ...data } = route;
    const ref = db.collection('routes').doc(id);
    routeBatch.set(ref, data);
  }
  await routeBatch.commit();
  console.log('✅ Routes seeded!\n');

  console.log('🎉 Firestore seed complete!');
  console.log(`   ${busStops.length} bus stops`);
  console.log(`   ${routes.length} routes`);
  process.exit(0);
}

seedData().catch((err) => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
