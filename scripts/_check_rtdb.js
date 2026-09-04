const { initializeApp, cert } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const path = require('path');
const sa = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(sa), databaseURL: `https://${sa.project_id}-default-rtdb.firebaseio.com` });
const db = getDatabase();

async function main() {
  try {
    const ref = db.ref('/');
    const snap = await ref.orderByKey().limitToFirst(20).once('value');
    console.log('RTDB ROOT:');
    console.log(JSON.stringify(snap.val(), null, 2));
  } catch (e) {
    console.log('RTDB not available:', e.message);
  }
  process.exit(0);
}
main();
