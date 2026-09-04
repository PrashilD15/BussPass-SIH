const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');
const serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
const db = getFirestore();

async function main() {
  console.log('=== Collections ===');
  const cols = await db.listCollections();
  for (const c of cols) console.log('  -', c.id);

  console.log('\n=== Route with stops (Mumbai-Pune) ===');
  const r = await db.collection('routes').doc('mumbai-dadar-pune-swargate').get();
  if (r.exists) {
    const d = r.data();
    console.log('  name:', d.name);
    console.log('  distance_km:', d.distance_km);
    console.log('  bus_types:', d.bus_types);
    console.log('  fare_min/max:', d.fare_min, '/', d.fare_max);
    console.log('  stops:');
    for (const s of d.stops) console.log(`    ${s.seq}. ${s.city} (${s.stop_id}) @${s.cum_km}km (${s.lat},${s.lng})`);
  }

  console.log('\n=== route_fares (Mumbai-Pune) ===');
  const f = await db.collection('route_fares').doc('mumbai-dadar-pune-swargate').get();
  if (f.exists) {
    const d = f.data();
    console.log('  by_type (full route):');
    for (const [t, p] of Object.entries(d.by_type)) console.log(`    ${t}: ₹${p}`);
    console.log('  segments (sample):');
    for (const [k, v] of Object.entries(d.segments)) {
      console.log(`    ${k}: ${v.from} -> ${v.to}, ${v.distanceKm}km, byType=${JSON.stringify(v.byType)}`);
    }
  }

  console.log('\n=== Counts ===');
  for (const name of ['routes', 'route_fares', 'bus_stops']) {
    const s = await db.collection(name).get();
    console.log(`  ${name}: ${s.size}`);
  }
  process.exit(0);
}
main().catch(e => { console.error('❌', e.message); process.exit(1); });
