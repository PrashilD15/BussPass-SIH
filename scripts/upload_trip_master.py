#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 Trip Master Excel → Firestore Uploader
=============================================================================
 Reads Trip_Master_17092026_131814.xlsx (10,961 active trips) and uploads
 to Firestore collection: 'trip_master'

 Schema per document (keyed by Trip Code):
 {
   "trip_code": "00185663",
   "origin": "WARI(KANHEGAON STN.",
   "destination": "KOPARGAON",
   "origin_norm": "wari(kanhegaon stn.",   # lowercase for search
   "destination_norm": "kopargaon",
   "route_number": "48136",
   "route_description": "WARI(KANHEGAON STN. TO KOPARGAON",
   "via_stops": ["JORVE"],                  # extracted from route name
   "distance_km": 21.3,
   "departure_time": "13:15",
   "arrival_time": "13:54",
   "departure_minutes": 795,               # minutes from midnight for fast sort
   "trip_type": "Normal",
   "trip_days": 0,                         # 0=daily, 1=weekday, 2=special...
   "status": "Active"
 }

 Also creates a 'trip_routes' collection grouping trips by route_number,
 with all departure times for fast bulk lookup.
=============================================================================
"""

import os
import sys
import json
import datetime

# ---------------------------------------------------------------------------
# Parse openpyxl
# ---------------------------------------------------------------------------
try:
    import openpyxl
except ImportError:
    print("Installing openpyxl...")
    os.system(f"{sys.executable} -m pip install openpyxl -q")
    import openpyxl

# ---------------------------------------------------------------------------
# Firebase Init
# ---------------------------------------------------------------------------
base_dir = os.path.dirname(os.path.abspath(__file__))
db = None
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    key_path = os.path.join(base_dir, 'scripts', 'serviceAccountKey.json')
    if not os.path.exists(key_path):
        key_path = os.path.join(base_dir, 'serviceAccountKey.json')
    cred = credentials.Certificate(key_path)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print(f"✅ Firestore Connected: {cred.project_id}")
except Exception as e:
    print(f"❌ Firestore error: {e}")
    sys.exit(1)


def parse_time_to_minutes(t_str):
    """Convert 'HH:MM' or '13:15' to minutes from midnight."""
    try:
        parts = str(t_str).strip().split(':')
        return int(parts[0]) * 60 + int(parts[1][:2])
    except Exception:
        return 0


def extract_via_stops(route_description):
    """Extract via stop names from route description like 'A TO B VIA X AND Y'."""
    if not route_description:
        return []
    desc = str(route_description).upper()
    if 'VIA' not in desc:
        return []
    via_part = desc.split('VIA', 1)[1].strip()
    # Split on common delimiters
    via_part = via_part.replace(' AND ', ',').replace('&', ',')
    stops = [s.strip().title() for s in via_part.split(',') if s.strip()]
    return stops[:5]  # max 5 via stops


def parse_route_number(route_str):
    """Extract numeric route number from '48136 (WARI... TO ...)' format."""
    if not route_str:
        return ""
    return str(route_str).split('(')[0].strip()


def normalize(text):
    """Lowercase + strip for search normalization."""
    return str(text).lower().strip() if text else ""


def upload_trip_master(xlsx_path, dry_run=False, batch_size=400):
    """
    Read Excel and upload to Firestore.
    Uses batched writes for efficiency (Firestore limit: 500 ops/batch).
    """
    print(f"\n📖 Reading {xlsx_path}...")
    wb = openpyxl.load_workbook(xlsx_path, read_only=True)
    ws = wb['Trip Master']
    rows = list(ws.iter_rows(min_row=12, values_only=True))
    print(f"   Rows read: {len(rows)}")

    # Filter valid active rows
    valid_rows = [r for r in rows if r[0] and r[1] and r[2] and r[9] == 'Active']
    print(f"   Active trips: {len(valid_rows)}")

    if dry_run:
        print("\n🔍 DRY RUN — showing first 5 records:")
        for r in valid_rows[:5]:
            print(f"   {r}")
        return

    # ------------------------------------------------------------------
    # Upload to 'trip_master' collection
    # ------------------------------------------------------------------
    print(f"\n⬆️  Uploading to Firestore 'trip_master' collection...")
    print(f"   Batch size: {batch_size}")

    total_uploaded = 0
    skipped = 0
    batch = db.batch()
    batch_count = 0

    # Group by route for 'trip_routes' collection simultaneously
    route_groups = {}  # route_number -> list of departure dicts

    for row in valid_rows:
        trip_code     = str(row[0]).strip()
        origin        = str(row[1]).strip().upper() if row[1] else ""
        destination   = str(row[2]).strip().upper() if row[2] else ""
        route_str     = str(row[3]).strip() if row[3] else ""
        distance_km   = float(row[4]) if row[4] else 0.0
        dep_time      = str(row[5]).strip() if row[5] else ""
        arr_time      = str(row[6]).strip() if row[6] else ""
        trip_type     = str(row[7]).strip() if row[7] else "Normal"
        trip_days     = int(row[8]) if row[8] is not None else 0
        status        = str(row[9]).strip() if row[9] else "Active"

        if not origin or not destination or not dep_time:
            skipped += 1
            continue

        route_num = parse_route_number(route_str)
        via_stops = extract_via_stops(route_str)
        dep_mins  = parse_time_to_minutes(dep_time)
        arr_mins  = parse_time_to_minutes(arr_time)

        doc_data = {
            "trip_code":          trip_code,
            "origin":             origin,
            "destination":        destination,
            "origin_norm":        normalize(origin),
            "destination_norm":   normalize(destination),
            "route_number":       route_num,
            "route_description":  route_str,
            "via_stops":          via_stops,
            "distance_km":        distance_km,
            "departure_time":     dep_time,
            "arrival_time":       arr_time,
            "departure_minutes":  dep_mins,
            "arrival_minutes":    arr_mins,
            "trip_type":          trip_type,
            "trip_days":          trip_days,
            "status":             status,
        }

        doc_id = trip_code.replace("/", "_").replace("\\", "_")
        doc_ref = db.collection("trip_master").document(doc_id)
        batch.set(doc_ref, doc_data)
        batch_count += 1

        # Accumulate for route_groups
        if route_num:
            if route_num not in route_groups:
                route_groups[route_num] = {
                    "route_number":   route_num,
                    "route_description": route_str,
                    "origin":         origin,
                    "destination":    destination,
                    "origin_norm":    normalize(origin),
                    "destination_norm": normalize(destination),
                    "via_stops":      via_stops,
                    "distance_km":    distance_km,
                    "departures":     []
                }
            route_groups[route_num]["departures"].append({
                "trip_code":       trip_code,
                "departure_time":  dep_time,
                "arrival_time":    arr_time,
                "departure_minutes": dep_mins,
                "trip_days":       trip_days,
            })

        # Commit when batch is full
        if batch_count >= batch_size:
            batch.commit()
            total_uploaded += batch_count
            print(f"   ✅ Committed {total_uploaded} / {len(valid_rows)} trips...")
            batch = db.batch()
            batch_count = 0

    # Commit remaining
    if batch_count > 0:
        batch.commit()
        total_uploaded += batch_count

    print(f"\n✅ trip_master: {total_uploaded} trips uploaded. Skipped: {skipped}")

    # ------------------------------------------------------------------
    # Upload to 'trip_routes' collection (grouped by route_number)
    # ------------------------------------------------------------------
    print(f"\n⬆️  Uploading to Firestore 'trip_routes' collection...")
    print(f"   Unique routes to upload: {len(route_groups)}")

    route_batch = db.batch()
    route_count = 0
    total_routes = 0

    for route_num, route_data in route_groups.items():
        # Sort departures by time
        route_data["departures"].sort(key=lambda x: x["departure_minutes"])
        route_data["total_trips"] = len(route_data["departures"])
        route_data["first_departure"] = route_data["departures"][0]["departure_time"] if route_data["departures"] else ""
        route_data["last_departure"] = route_data["departures"][-1]["departure_time"] if route_data["departures"] else ""

        doc_ref = db.collection("trip_routes").document(route_num)
        route_batch.set(doc_ref, route_data)
        route_count += 1

        if route_count >= batch_size:
            route_batch.commit()
            total_routes += route_count
            print(f"   ✅ Committed {total_routes} / {len(route_groups)} routes...")
            route_batch = db.batch()
            route_count = 0

    if route_count > 0:
        route_batch.commit()
        total_routes += route_count

    print(f"\n✅ trip_routes: {total_routes} route groups uploaded.")
    print(f"\n🎉 DONE! Firestore now has:")
    print(f"   - trip_master:  {total_uploaded} individual trip records")
    print(f"   - trip_routes:  {total_routes} route groups with grouped timetables")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Upload Trip Master Excel to Firestore")
    parser.add_argument("--dry-run", action="store_true", help="Parse only, do not upload")
    parser.add_argument("--xlsx", default="Trip_Master_17092026_131814.xlsx", help="Excel file path")
    args = parser.parse_args()

    xlsx_path = os.path.join(base_dir, args.xlsx)
    if not os.path.exists(xlsx_path):
        print(f"❌ File not found: {xlsx_path}")
        sys.exit(1)

    upload_trip_master(xlsx_path, dry_run=args.dry_run)
