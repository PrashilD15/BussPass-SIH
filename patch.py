import re

with open("msrtc_human_ai_agent.py", "r") as f:
    content = f.read()

replacement = """def _get_trip_master_cached():
    global _trip_master_cache
    if _trip_master_cache is not None:
        return _trip_master_cache
    
    _trip_master_cache = []
    try:
        import time
        now = time.time()
        print("⏳ [TripRoutes] Fetching 'trip_routes' from Firestore (this may take a few seconds)...")
        from google.cloud import firestore
        docs = db.collection("trip_routes").get()
        
        for d in docs:
            r = d.to_dict()
            _trip_master_cache.append({
                "origin": r.get("origin", "").upper(),
                "destination": r.get("destination", "").upper(),
                "origin_norm": r.get("origin_norm", "").lower(),
                "destination_norm": r.get("destination_norm", "").lower(),
                "route_description": r.get("route_description", ""),
                "via_stops": r.get("via_stops", []),
                "distance_km": float(r.get("distance_km", 0.0)),
                "departures": r.get("departures", []),
            })
            
        print(f"✅ [TripRoutes] Loaded {len(_trip_master_cache)} grouped routes from Firestore.")
    except Exception as e:
        print(f"⚠️ [TripRoutes] Firestore load error: {e}")

    return _trip_master_cache

def _search_trip_master(origin_query: str, dest_query: str, current_minutes: int) -> list:
    trips = _get_trip_master_cached()
    if not trips:
        return []

    orig_q = origin_query.strip().lower()
    dest_q = dest_query.strip().lower()

    matched = []
    for t in trips:
        orig_match = _fuzzy_city_match(orig_q, t["origin_norm"])
        dest_match = _fuzzy_city_match(dest_q, t["destination_norm"])
        
        is_reverse = False
        if not (orig_match and dest_match):
            if _fuzzy_city_match(dest_q, t["origin_norm"]) and _fuzzy_city_match(orig_q, t["destination_norm"]):
                orig_match = True
                dest_match = True
                is_reverse = True

        if dest_match and orig_match:
            for dep in t.get("departures", []):
                diff = dep.get("departure_minutes", 0) - current_minutes
                if diff < -60:
                    diff += 1440
                if diff >= 0:
                    trip_copy = dict(t)
                    trip_copy["departure_minutes"] = dep.get("departure_minutes", 0)
                    trip_copy["departure_time"] = dep.get("departure_time", "00:00")
                    trip_copy["arrival_time"] = dep.get("arrival_time", "")
                    trip_copy["minutes_from_now"] = diff
                    if is_reverse:
                        trip_copy["origin"] = dest_query.title()
                        trip_copy["destination"] = origin_query.title()
                        trip_copy["route_description"] = f"{dest_query.upper()} - {origin_query.upper()} (Reverse Route)"
                    matched.append(trip_copy)

    matched.sort(key=lambda x: x["minutes_from_now"])
    top3 = matched[:3]
"""

# Find the start of _get_trip_master_cached and the start of the shape output logic
pattern = re.compile(r"def _get_trip_master_cached\(\):.*?matched\.sort\(key=lambda x: x\[\"minutes_from_now\"\]\)\n    top3 = matched\[:3\]", re.DOTALL)

new_content = pattern.sub(replacement, content)

with open("msrtc_human_ai_agent.py", "w") as f:
    f.write(new_content)

print("Patched msrtc_human_ai_agent.py")
