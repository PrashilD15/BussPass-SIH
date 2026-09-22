const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');

const KEY_PATH = path.join(__dirname, 'serviceAccountKey.json');
const serviceAccount = require(KEY_PATH);

initializeApp({
  credential: cert(serviceAccount),
  storageBucket: 'busspass-58583.firebasestorage.app'
});

const bucket = getStorage().bucket();
const imagesDir = path.join(__dirname, '../Bus-images');

async function uploadImages() {
  const files = fs.readdirSync(imagesDir).filter(f => f.match(/\.(jpg|jpeg|png)$/));
  for (const file of files) {
    const localPath = path.join(imagesDir, file);
    const destPath = 'bus_images/' + file;
    console.log(`Uploading ${file}...`);
    
    await bucket.upload(localPath, {
      destination: destPath,
      metadata: {
        cacheControl: 'public, max-age=31536000',
      },
    });

    // Make the file publicly accessible and get the download URL
    const fileRef = bucket.file(destPath);
    await fileRef.makePublic();
    const url = `https://storage.googleapis.com/${bucket.name}/${encodeURIComponent(destPath)}`;
    console.log(`Uploaded ${file}: ${url}`);
  }
}

uploadImages().catch(console.error);
