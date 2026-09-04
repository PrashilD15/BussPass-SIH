const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');
const serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
const db = getFirestore();

async function main() {
  // Old data (pre-this-session) was dumped to a file; recompute from git is hard,
  // so compare the CURRENT routes fare_min/max against routes that had STOPS added.
  // We'll print a comparison report of routes that changed.
  const snap = await db.collection('routes').get();
  const routes = [];
  snap.forEach((d) => routes.push({ id: d.id, ...d.data() }));

  // Sort by fare_min for readability
  routes.sort((a, b) => a.fare_min - b.fare_min);

  console.log('=== Current routes after July 2026 fare revision (sorted by Ordinary fare) ===');
  console.log('Route | km | stops | fare_min | fare_max | bus_types');
  for (const r of routes) {
    const stopsN = (r.stops || []).length;
    console.log(
      `${r.origin_city}->${r.destination_city} | ${r.distance_km} | ${stopsN} | ₹${r.fare_min} | ₹${r.fare_max} | ${r.bus_types.join(',')}`
    );
  }

  // Summarize the fare matrix
  console.log('\n=== Fare matrix summary (per route total, by type) ===');
  let totalSegments = 0;
  for (const r of routes) {
    const fdoc = await db.collection('route_fares').doc(r.id).get();
    if (!fdoc.exists) continue;
    totalSegments += Object.keys(fdoc.data().segments || {}).length;
  }
  console.log(`Total stop-pair fare segments across all routes: ${totalSegments}`);

  process.exit(0);
}
main().catch(e => { console.error('❌', e.message); process.exit(1); });
