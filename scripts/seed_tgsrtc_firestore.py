import os
import json
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# Initialize Firebase
cred = credentials.Certificate("scripts/serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Load TGSRTC network data
with open("busspass/assets/data/tgsrtc_network.json", "r") as f:
    data = json.load(f)

print("Seeding TGSRTC data to Firestore...")

# Seed Stops
print(f"Seeding {len(data['stops'])} stops...")
for stop in data['stops']:
    stop_id = stop['id']
    doc_ref = db.collection('bus_stops').document(stop_id)
    doc_ref.set(stop)
    print(f"  -> {stop['name']}")

# Seed Routes
print(f"Seeding {len(data['routes'])} routes...")
for route in data['routes']:
    route_id = route['id']
    doc_ref = db.collection('routes').document(route_id)
    doc_ref.set(route)
    print(f"  -> {route['name']}")

print("\nTGSRTC seed complete! The Flutter app will now pull this data dynamically when in Telangana.")
