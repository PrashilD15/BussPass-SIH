const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');

const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();
const timetablesPath = '../busspass/assets/data/timetables.json';

async function seed() {
  try {
    const rawData = fs.readFileSync(timetablesPath, 'utf8');
    const data = JSON.parse(rawData);

    const batch = db.batch();
    const collectionRef = db.collection('timetables');

    for (let i = 0; i < data.length; i++) {
      const item = data[i];
      // Use auto-generated document ID to avoid issues with non-alphanumeric characters
      const docRef = collectionRef.doc();
      batch.set(docRef, item, { merge: true });
    }

    await batch.commit();
    console.log(`Successfully seeded ${data.length} timetables to Firestore!`);
  } catch (error) {
    console.error('Error seeding data:', error);
  }
}

seed();
