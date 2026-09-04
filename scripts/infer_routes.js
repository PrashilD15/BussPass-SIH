const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function run() {
  const timetablesSnap = await db.collection('timetables').get();
  console.log(`Loaded ${timetablesSnap.size} timetables.`);

  let batch = db.batch();
  let opCount = 0;

  for (const doc of timetablesSnap.docs) {
    const tt = doc.data();
    if (!tt.origin_city || !tt.destination_city) continue;

    const originStopId = tt.origin_city.toLowerCase().replace(/\s/g, '-');
    const destStopId = tt.destination_city.toLowerCase().replace(/\s/g, '-');
    const routeId = `${originStopId}-${destStopId}`;

    const routeRef = db.collection('routes').doc(routeId);
    
    // We only set basic direct route details.
    // The stops array will just be [origin, destination] for now.
    batch.set(routeRef, {
      name: `${tt.origin_city} – ${tt.destination_city}`,
      origin_stop_id: originStopId,
      destination_stop_id: destStopId,
      origin_city: tt.origin_city,
      destination_city: tt.destination_city,
      distance_km: tt.distance_km || 0,
      duration_hrs: 'Unknown',
      fare_min: tt.distance_km > 0 ? Math.floor(tt.distance_km * 1.5) : 50, // rough estimate
      fare_max: tt.distance_km > 0 ? Math.floor(tt.distance_km * 2.0) : 100,
      bus_types: [tt.bus_type || 'Ordinary'],
      first_bus: tt.departure_times && tt.departure_times.length > 0 ? tt.departure_times[0] : 'N/A',
      last_bus: tt.departure_times && tt.departure_times.length > 1 ? tt.departure_times[tt.departure_times.length - 1] : 'N/A',
      stops: [
        {
          stop_id: originStopId,
          name: `${tt.origin_city} Bus Stand`,
          city: tt.origin_city,
          lat: 19.5, lng: 74.5,
          seq: 1, cum_km: 0
        },
        {
          stop_id: destStopId,
          name: `${tt.destination_city} Bus Stand`,
          city: tt.destination_city,
          lat: 19.5, lng: 74.5,
          seq: 2, cum_km: tt.distance_km || 0
        }
      ]
    }, { merge: true }); // merge to avoid overwriting existing detailed routes (like Pune-Nashik)

    opCount++;
    if (opCount >= 400) {
      await batch.commit();
      console.log('Committed batch of routes...');
      batch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
    console.log('Committed final batch of routes.');
  }

  console.log('Done inferring direct routes.');
}

run().catch(console.error);
