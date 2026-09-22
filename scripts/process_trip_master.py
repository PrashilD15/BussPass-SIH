#!/usr/bin/env python3
"""
process_trip_master.py
======================
Parses Trip_Master_17092026_131814.xlsx (official MSRTC Ahilyanagar trip data)
and merges the results into busspass/assets/data/network.json.
"""

import json
import re
import sys
import shutil
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timezone

try:
    import openpyxl
except ImportError:
    sys.exit("openpyxl not found")

REPO_ROOT = Path(__file__).parent.parent
XLSX_PATH = REPO_ROOT / "Trip_Master_17092026_131814.xlsx"
NETWORK_PATH = REPO_ROOT / "busspass" / "assets" / "data" / "network.json"
BACKUP_PATH = NETWORK_PATH.with_suffix(".json.bak")

AHILYANAGAR_COORDS = {
    "AHMEDNAGAR":               {"lat": 19.0948, "lng": 74.7480, "tier": 3},
    "AHILYA NAGAR":             {"lat": 19.0948, "lng": 74.7480, "tier": 3},
    "AHILYA NAGAR MALIWADA":    {"lat": 19.0948, "lng": 74.7480, "tier": 3},
    "AHMEDNAGAR MALIWADA":      {"lat": 19.0948, "lng": 74.7480, "tier": 3},
    "AKOLE":                    {"lat": 19.5340, "lng": 73.9328, "tier": 2},
    "ARANGAON":                 {"lat": 17.9547, "lng": 75.3780, "tier": 1},
    "BELAPUR":                  {"lat": 19.0207, "lng": 73.0369, "tier": 1},
    "BHINGAR":                  {"lat": 19.1284, "lng": 74.8103, "tier": 1},
    "BUDHEWADI":                {"lat": 19.1100, "lng": 74.7900, "tier": 1},
    "CHITALI":                  {"lat": 19.2900, "lng": 74.6000, "tier": 1},
    "DHOKI":                    {"lat": 19.1600, "lng": 74.8100, "tier": 1},
    "GHULEWADI":                {"lat": 19.1000, "lng": 74.8000, "tier": 1},
    "JAMKHED":                  {"lat": 18.7244, "lng": 75.3261, "tier": 2},
    "JAWALA":                   {"lat": 18.7500, "lng": 75.2500, "tier": 1},
    "JORVE":                    {"lat": 19.5700, "lng": 74.4500, "tier": 1},
    "KASBE SUKENE":             {"lat": 19.1800, "lng": 74.9200, "tier": 1},
    "KEDGAON":                  {"lat": 18.7000, "lng": 74.4300, "tier": 1},
    "KHARDA":                   {"lat": 19.1490, "lng": 74.6520, "tier": 1},
    "KOLHAR":                   {"lat": 19.1000, "lng": 74.5400, "tier": 1},
    "KOPARGAON":                {"lat": 19.8966, "lng": 74.4780, "tier": 2},
    "LONI":                     {"lat": 19.5780, "lng": 74.4620, "tier": 1},
    "MANCHAR":                  {"lat": 18.8200, "lng": 73.9200, "tier": 1},
    "MIRAJGAON":                {"lat": 19.1700, "lng": 74.6700, "tier": 1},
    "NAGAR":                    {"lat": 19.0948, "lng": 74.7480, "tier": 2},
    "NEVASA":                   {"lat": 19.5530, "lng": 75.0010, "tier": 2},
    "NEWASA":                   {"lat": 19.5530, "lng": 75.0010, "tier": 2},
    "NIGHOJ":                   {"lat": 18.8600, "lng": 74.2800, "tier": 1},
    "PARNER":                   {"lat": 19.0014, "lng": 74.4380, "tier": 2},
    "PATHARDI":                 {"lat": 19.1880, "lng": 75.1870, "tier": 2},
    "PIMPRI(PATHARDI)":         {"lat": 19.2100, "lng": 75.1500, "tier": 1},
    "RAHATA":                   {"lat": 19.7230, "lng": 74.4830, "tier": 1},
    "RAHURI":                   {"lat": 19.3920, "lng": 74.6470, "tier": 2},
    "RAJUR":                    {"lat": 19.4600, "lng": 73.7200, "tier": 1},
    "SANGAMNER":                {"lat": 19.5740, "lng": 74.2100, "tier": 2},
    "SAVEDI":                   {"lat": 19.0700, "lng": 74.7600, "tier": 1},
    "SHEVGAON":                 {"lat": 19.3110, "lng": 75.6980, "tier": 2},
    "SHIRDI":                   {"lat": 19.7666, "lng": 74.4777, "tier": 2},
    "SHRIGONDA":                {"lat": 18.6117, "lng": 74.6980, "tier": 2},
    "SHRIRAMPUR":               {"lat": 19.6250, "lng": 74.6520, "tier": 2},
    "SUPA":                     {"lat": 19.0200, "lng": 74.5600, "tier": 1},
    "TAKALI DHOKESHWAR":        {"lat": 19.2600, "lng": 74.3500, "tier": 1},
    "VAMBORI":                  {"lat": 19.4200, "lng": 74.7100, "tier": 1},
    "WARI(KANHEGAON STN.":      {"lat": 19.8900, "lng": 74.4800, "tier": 1},
    "WARI":                     {"lat": 19.8900, "lng": 74.4800, "tier": 1},
    "NASHIK CBS":               {"lat": 19.9975, "lng": 73.7898, "tier": 3},
    "NASHIK":                   {"lat": 19.9975, "lng": 73.7898, "tier": 3},
    "PUNE SWARGATE":            {"lat": 18.5018, "lng": 73.8576, "tier": 3},
    "NEW SHIVAJI NAGAR PUNE":   {"lat": 18.5354, "lng": 73.8474, "tier": 2},
    "PUNE":                     {"lat": 18.5018, "lng": 73.8576, "tier": 3},
    "TRIAMBAK":                 {"lat": 19.9290, "lng": 73.5310, "tier": 1},
    "TRIMBAK":                  {"lat": 19.9290, "lng": 73.5310, "tier": 1},
    "LATUR":                    {"lat": 18.4088, "lng": 76.5604, "tier": 3},
    "SOLAPUR":                  {"lat": 17.6868, "lng": 75.9010, "tier": 3},
    "MUMBAI":                   {"lat": 18.9396, "lng": 72.8353, "tier": 3},
    "AURANGABAD":               {"lat": 19.8762, "lng": 75.3433, "tier": 3},
    "PANDHARPUR":               {"lat": 17.6809, "lng": 75.3300, "tier": 2},
    "PARBHANI":                 {"lat": 19.2700, "lng": 76.7740, "tier": 2},
    "NANDED":                   {"lat": 19.1383, "lng": 77.3210, "tier": 3},
    "JALNA":                    {"lat": 19.8447, "lng": 75.8816, "tier": 2},
}

def slugify(name):
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

def time_to_minutes(t):
    if not t:
        return None
    try:
        h, m = str(t).strip().split(":")
        return int(h) * 60 + int(m)
    except Exception:
        return None

def normalize(raw):
    return raw.strip().upper()

def main():
    print(f"Reading {XLSX_PATH.name} ...")
    wb = openpyxl.load_workbook(str(XLSX_PATH))
    ws = wb.active

    header_row_idx = None
    for r_idx, row in enumerate(ws.iter_rows(max_row=30, values_only=True), 1):
        if row[0] == "Trip Code":
            header_row_idx = r_idx
            header = row
            break
    if header_row_idx is None:
        sys.exit("Could not find header row")

    col = {v: i for i, v in enumerate(header)}
    print(f"  Header found at row {header_row_idx}")

    trips = []
    skipped = 0
    for row in ws.iter_rows(min_row=header_row_idx + 1, values_only=True):
        if not row[col["Trip Code"]]:
            continue
        if str(row[col["Status"]] or "").strip().lower() != "active":
            continue
        duty_from = str(row[col["Duty From"]] or "").strip()
        duty_to = str(row[col["Duty To"]] or "").strip()
        dist_raw = str(row[col["Distance (KM)"]] or "").strip()
        dep_time = str(row[col["Departure Time"]] or "").strip()
        try:
            dist_km = float(dist_raw)
        except ValueError:
            dist_km = 0.0
        dep_min = time_to_minutes(dep_time)
        if dep_min is None or not duty_from or not duty_to:
            skipped += 1
            continue
        trips.append({
            "from": duty_from,
            "to": duty_to,
            "dist_km": dist_km,
            "dep_min": dep_min,
        })

    print(f"  Loaded {len(trips):,} active trips ({skipped} skipped)")

    print(f"\nLoading {NETWORK_PATH.name} ...")
    with open(NETWORK_PATH, encoding="utf-8") as f:
        network = json.load(f)

    existing_stops = network.setdefault("stops", [])
    existing_routes = network.setdefault("routes", [])
    existing_services = network.setdefault("services", [])
    existing_timetables = network.setdefault("timetables", [])

    print(f"  Existing: {len(existing_stops)} stops, {len(existing_routes)} routes, "
          f"{len(existing_services)} services, {len(existing_timetables)} timetables")

    stop_name_to_id = {}
    for s in existing_stops:
        for field in ("city", "name", "depot"):
            key = str(s.get(field, "")).strip().upper()
            if key:
                stop_name_to_id[key] = s["id"]
    stop_id_to_obj = {s["id"]: s for s in existing_stops}

    no_coords = set()

    def get_or_create_stop(raw_name):
        norm = normalize(raw_name)
        if norm in stop_name_to_id:
            return stop_name_to_id[norm]

        # Explicit alias resolution
        aliases = {
            "AHILYA NAGAR MALIWADA": "AHMEDNAGAR",
            "AHMEDNAGAR MALIWADA": "AHMEDNAGAR",
        }
        if norm in aliases:
            alt = aliases[norm]
            if alt in stop_name_to_id:
                stop_name_to_id[norm] = stop_name_to_id[alt]
                return stop_name_to_id[alt]

        if norm not in AHILYANAGAR_COORDS:
            no_coords.add(norm)
            return None

        coords = AHILYANAGAR_COORDS[norm]
        new_id = slugify(raw_name)
        if new_id in stop_id_to_obj:
            new_id = new_id + "-an"

        new_stop = {
            "id": new_id,
            "name": raw_name.title() + " Bus Stand",
            "city": raw_name.title(),
            "depot": raw_name.title(),
            "district": "Ahilyanagar",
            "lat": coords["lat"],
            "lng": coords["lng"],
            "tier": coords.get("tier", 1),
        }
        existing_stops.append(new_stop)
        stop_id_to_obj[new_id] = new_stop
        stop_name_to_id[norm] = new_id
        return new_id

    route_trips = defaultdict(list)
    for t in trips:
        route_trips[(t["from"], t["to"])].append(t)

    # Timetable dedup index
    tt_key_to_idx = {}
    for i, tt in enumerate(existing_timetables):
        key = (tt.get("origin_stop_id", ""), str(tt.get("destination", "")).upper())
        tt_key_to_idx[key] = i

    route_id_set = {r["id"] for r in existing_routes}
    svc_id_set = {s["id"] for s in existing_services}

    new_tt = 0
    upd_tt = 0
    new_r = 0
    new_s = 0
    svc_counter = len(existing_services)

    for (from_name, to_name), t_list in route_trips.items():
        from_id = get_or_create_stop(from_name)
        to_id = get_or_create_stop(to_name)
        if from_id is None or to_id is None:
            continue

        dist_km = max((t["dist_km"] for t in t_list if t["dist_km"] > 0), default=0.0)
        departures = sorted({t["dep_min"] for t in t_list})

        from_obj = stop_id_to_obj[from_id]
        to_obj = stop_id_to_obj[to_id]

        # Timetable
        tt_key = (from_id, to_name.upper())
        if tt_key in tt_key_to_idx:
            idx = tt_key_to_idx[tt_key]
            existing_deps = set(existing_timetables[idx]["departures"])
            merged = sorted(existing_deps | set(departures))
            if merged != existing_timetables[idx]["departures"]:
                existing_timetables[idx]["departures"] = merged
                upd_tt += 1
        else:
            existing_timetables.append({
                "origin_stop_id": from_id,
                "origin_city": from_obj.get("city", from_name.title()),
                "destination": to_name.title(),
                "destination_stop_id": to_id,
                "via": [],
                "bus_type": "Ordinary",
                "distance_km": dist_km if dist_km > 0 else None,
                "departures": departures,
            })
            tt_key_to_idx[tt_key] = len(existing_timetables) - 1
            new_tt += 1

        # Route
        rid = f"{from_id}--{to_id}"
        if rid not in route_id_set:
            existing_routes.append({
                "id": rid,
                "name": f"{from_obj.get('city', from_name.title())} \u2013 {to_obj.get('city', to_name.title())}",
                "operator": "MSRTC",
                "corridor": False,
                "origin_stop_id": from_id,
                "destination_stop_id": to_id,
                "origin_city": from_obj.get("city", from_name.title()),
                "destination_city": to_obj.get("city", to_name.title()),
                "distance_km": dist_km,
                "bus_types": ["Ordinary"],
                "stops": [
                    {"stop_id": from_id, "name": from_obj.get("name", ""), "city": from_obj.get("city", ""),
                     "lat": from_obj.get("lat", 0), "lng": from_obj.get("lng", 0), "seq": 1, "cum_km": 0},
                    {"stop_id": to_id, "name": to_obj.get("name", ""), "city": to_obj.get("city", ""),
                     "lat": to_obj.get("lat", 0), "lng": to_obj.get("lng", 0), "seq": 2, "cum_km": dist_km},
                ],
            })
            route_id_set.add(rid)
            new_r += 1

            svc_id = f"svc-xlsx-{svc_counter}"
            svc_counter += 1
            if svc_id not in svc_id_set:
                existing_services.append({
                    "id": svc_id,
                    "route_id": rid,
                    "bus_type": "Ordinary",
                    "source": "timetable",
                    "from_stop_id": from_id,
                    "departures": departures,
                })
                svc_id_set.add(svc_id)
                new_s += 1

    network["version"] = int(network.get("version", 3)) + 1
    network["generated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    network["source_note"] = (
        "Merged from Trip_Master_17092026_131814.xlsx (MSRTC Ahilyanagar official data) on "
        + datetime.now(timezone.utc).strftime("%Y-%m-%d")
    )

    shutil.copy(NETWORK_PATH, BACKUP_PATH)
    print(f"\nBackup saved to {BACKUP_PATH.name}")

    with open(NETWORK_PATH, "w", encoding="utf-8") as f:
        json.dump(network, f, ensure_ascii=False, indent=2)

    print(f"\nDone! Results:")
    print(f"  Stops:      {len(existing_stops)}")
    print(f"  Routes:     {len(existing_routes)}  (+{new_r} new)")
    print(f"  Services:   {len(existing_services)}  (+{new_s} new)")
    print(f"  Timetables: {len(existing_timetables)}  (+{new_tt} new, {upd_tt} updated)")
    print(f"  Version:    {network['version']}")

    if no_coords:
        print(f"\n  WARNING: {len(no_coords)} stop names had no coordinates (skipped):")
        for n in sorted(no_coords)[:20]:
            print(f"    - {n}")
        if len(no_coords) > 20:
            print(f"    ... and {len(no_coords)-20} more")

if __name__ == "__main__":
    main()
