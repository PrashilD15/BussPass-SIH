const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();
db.collection('timetables').limit(5).get().then(snap => {
  snap.forEach(doc => console.log(doc.data()));
  process.exit(0);
});
