const fs = require('fs');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

// Helper to convert Title Case
function toTitleCase(str) {
  return str.toLowerCase().split(' ').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
}

const slugToCity = {
  'akola-msrtc': 'Akole', // It's actually Akole in Ahmednagar based on distance
  'igatpuri': 'Igatpuri',
  'jamkhed': 'Jamkhed',
  'kalwan': 'Kalwan',
  'kopargaon': 'Kopargaon',
  'lasalgaon': 'Lasalgaon',
  'malegaon': 'Malegaon',
  'manmad': 'Manmad',
  'nandgaon': 'Nandgaon',
  'nashik-1-msrtc': 'Nashik CBS',
  'nashik-2': 'Nashik Road',
  'newasa': 'Newasa',
  'parner': 'Parner',
  'pathardi': 'Pathardi',
  'pet-how-to-book-msrtc-bus-ticket-online': 'Peth',
  'pimpalgaon': 'Pimpalgaon',
  'sangamner': 'Sangamner',
  'satana': 'Satana',
  'shevgaon': 'Shevgaon',
  'shirdi': 'Shirdi',
  'shrigonda': 'Shrigonda',
  'shrirampur': 'Shrirampur',
  'sinnar': 'Sinnar',
  'tarakpur': 'Tarakpur',
  'yeola-msrtc-bus-timings': 'Yeola'
};

async function run() {
  const rawData = JSON.parse(fs.readFileSync('../master_timetables.json', 'utf-8'));
  console.log(`Loaded ${rawData.length} scraped routes.`);

  let batch = db.batch();
  let opCount = 0;
  
  // Keep track of unique cities
  const uniqueCities = new Set();
  
  const existingStopsSnap = await db.collection('bus_stops').get();
  const existingStops = new Set();
  existingStopsSnap.forEach(doc => existingStops.add(doc.data().city.toLowerCase()));

  for (const item of rawData) {
    if (!item.destination || !item.origin_slug) continue;

    const originCity = slugToCity[item.origin_slug] || toTitleCase(item.origin_slug.replace('-msrtc', '').replace('-', ' '));
    const destCity = toTitleCase(item.destination);
    
    uniqueCities.add(originCity);
    uniqueCities.add(destCity);

    // Filter valid times
    const validTimes = item.times.filter(t => t.includes('AM') || t.includes('PM'));
    if (validTimes.length === 0) continue;

    // Create Timetable Entry
    const ttId = `${originCity.toLowerCase().replace(/\\s/g, '')}_${destCity.toLowerCase().replace(/\\s/g, '')}_${item.bus_type.toLowerCase().replace(/\\s/g, '')}`.substring(0, 100);
    const ttRef = db.collection('timetables').doc(ttId);
    
    batch.set(ttRef, {
      origin_city: originCity,
      destination_city: destCity,
      bus_type: item.bus_type,
      distance_km: item.distance_km === 'Unknown' ? 0 : parseInt(item.distance_km, 10) || 0,
      departure_times: validTimes,
      updated_at: new Date().toISOString()
    }, { merge: true });
    
    opCount++;

    if (opCount >= 400) {
      await batch.commit();
      console.log('Committed batch of timetables...');
      batch = db.batch(); // Reinitialize batch
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
    console.log('Committed final batch of timetables.');
  }

  // Create missing Bus Stops
  let stopsBatch = db.batch();
  let stopsCount = 0;

  for (const city of uniqueCities) {
    if (!existingStops.has(city.toLowerCase())) {
      const stopId = city.toLowerCase().replace(/\s/g, '-');
      const stopRef = db.collection('bus_stops').doc(stopId);
      stopsBatch.set(stopRef, {
        name: `${city} Bus Stand`,
        city: city,
        depot: city,
        lat: 19.5, // Dummy default for central MH
        lng: 74.5  // Dummy default
      });
      stopsCount++;
      if (stopsCount >= 400) {
        await stopsBatch.commit();
        console.log('Committed batch of bus stops...');
        stopsBatch = db.batch(); // Reinitialize
        stopsCount = 0;
      }
    }
  }

  if (stopsCount > 0) {
    await stopsBatch.commit();
    console.log(`Committed ${stopsCount} new bus stops.`);
  }

  console.log('Done seeding bulk data.');
}

run().catch(console.error);
