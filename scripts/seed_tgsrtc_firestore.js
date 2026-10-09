const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const KEY_PATH = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(KEY_PATH)) {
  console.error('❌ serviceAccountKey.json not found in scripts/.');
  process.exit(1);
}

const serviceAccount = require(KEY_PATH);

initializeApp({
  credential: cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const db = getFirestore();

async function seedTGSRTC() {
  const dataPath = path.join(__dirname, '../busspass/assets/data/tgsrtc_network.json');
  const rawData = fs.readFileSync(dataPath, 'utf8');
  const data = JSON.parse(rawData);

  console.log(`Seeding TGSRTC data to Firestore...`);

  const batch = db.batch();

  // Seed Stops
  console.log(`Seeding ${data.stops.length} stops...`);
  for (const stop of data.stops) {
    stop.stc = 'TGSRTC';
    const docRef = db.collection('bus_stops').doc(stop.id);
    batch.set(docRef, stop);
    console.log(`  -> ${stop.name}`);
  }

  // Seed Routes
  console.log(`Seeding ${data.routes.length} routes...`);
  for (const route of data.routes) {
    route.stc = 'TGSRTC';
    const docRef = db.collection('routes').doc(route.id);
    batch.set(docRef, route);
    console.log(`  -> ${route.name}`);
  }

  await batch.commit();
  console.log('\n✅ TGSRTC seed complete! The Flutter app will now pull this data dynamically when in Telangana.');
}

seedTGSRTC().catch(console.error);
