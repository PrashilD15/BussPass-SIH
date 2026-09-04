const { initializeApp, cert } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
  storageBucket: 'busspass-58583.firebasestorage.app'
});

const bucket = getStorage().bucket();

const imagesDir = path.join(__dirname, '../Bus-images');

async function uploadImages() {
  const files = fs.readdirSync(imagesDir).filter(f => f.endsWith('.jpeg') || f.endsWith('.jpg') || f.endsWith('.png'));
  
  const urls = {};
  
  for (const file of files) {
    const filePath = path.join(imagesDir, file);
    const destination = `bus_images/${file}`;
    
    console.log(`Uploading ${file}...`);
    
    const uuid = crypto.randomUUID();
    
    await bucket.upload(filePath, {
      destination: destination,
      metadata: {
        metadata: {
          firebaseStorageDownloadTokens: uuid
        }
      }
    });
    
    const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destination)}?alt=media&token=${uuid}`;
    urls[file] = publicUrl;
    
    console.log(`Uploaded! URL: ${publicUrl}`);
  }
  
  console.log('All images uploaded.');
  fs.writeFileSync('uploaded_urls.json', JSON.stringify(urls, null, 2));
}

uploadImages().catch(console.error);
