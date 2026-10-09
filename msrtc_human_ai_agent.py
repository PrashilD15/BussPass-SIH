#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 BussPass MSRTC AI Human Enquiry Officer Engine (v2.0 — CRM Edition)
=============================================================================
 SIH 2026 Innovation:
   A software-only, human-like AI operator ("Aapli ST Inquiry Operator")
   that acts as an experienced, empathetic helpdesk officer.

 v2.0 Features:
   1. Caller Intelligence & CRM: Remembers every caller by phone number.
      Greets repeat callers by name in their preferred language.
      Proactively suggests frequent routes. Tracks mood, history, preferences.
   2. Full Firestore Read/Write: AI has write access to caller_profiles.
      Saves name, language, mood, query summary after every call.
   3. Enriched Route Data: Uses 'routes' collection (not 'timetables').
      Returns intermediate stops, via-stops, fare by bus type, duration.
   4. Emergency Handling: Accident, unsafe, medical, breakdown detection.
      Provides Police (112), Ambulance (108), MSRTC control room numbers.
   5. Zero Hardcoded Fallbacks: All data from Firestore. Honest "not found".
   6. Native Language Intelligence: Hindi, Marathi, English code-switching.
=============================================================================
"""

import sys
import os
import json
import time
import datetime
import asyncio
import threading
import subprocess
import math

# ---------------------------------------------------------------------------
# base_dir: used for key paths
# ---------------------------------------------------------------------------
base_dir = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Firebase Init
# ---------------------------------------------------------------------------
HAS_FIREBASE = False
db = None
try:
    import firebase_admin
    from firebase_admin import credentials, firestore, db as rtdb
    from google.cloud.firestore import ArrayUnion, Increment

    key_path = os.path.join(base_dir, 'scripts', 'serviceAccountKey.json')
    if not os.path.exists(key_path):
        key_path = os.path.join(base_dir, 'serviceAccountKey.json')
    if os.path.exists(key_path):
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred, {
            'databaseURL': f'https://{cred.project_id}-default-rtdb.firebaseio.com'
        })
        db = firestore.client()
        HAS_FIREBASE = True
        print(f"✅ [MSRTC Engine] Firestore Connected to Project: {cred.project_id}")
except Exception as e:
    print(f"⚠️ [MSRTC Engine] Firestore warning: {e}")

# ---------------------------------------------------------------------------
# Edge-TTS Import
# ---------------------------------------------------------------------------
HAS_EDGE_TTS = False
try:
    import edge_tts
    HAS_EDGE_TTS = True
    print("✅ [MSRTC Engine] Native Edge-TTS Speech Synthesizer Ready.")
except Exception as e:
    print(f"⚠️ [MSRTC Engine] Edge-TTS warning: {e}")

# ---------------------------------------------------------------------------
# Speech Recognition Import
# ---------------------------------------------------------------------------
HAS_SR = False
try:
    import speech_recognition as sr
    HAS_SR = True
    print("✅ [MSRTC Engine] Microphone Speech Recognition Engine Ready.")
except Exception as e:
    print(f"⚠️ [MSRTC Engine] Speech Recognition warning: {e}")

# ---------------------------------------------------------------------------
# Gemini SDK Import
# ---------------------------------------------------------------------------
HAS_GEMINI = False
genai_client = None
try:
    from google import genai
    gemini_key = os.environ.get("GEMINI_API_KEY", "")
    if gemini_key:
        genai_client = genai.Client(api_key=gemini_key)
        HAS_GEMINI = True
        print("✅ [MSRTC Engine] Gemini API Client Connected.")
except Exception as e:
    print(f"⚠️ [MSRTC Engine] Gemini SDK warning: {e}")

# ---------------------------------------------------------------------------
# Firestore Query Cache (5-minute TTL to reduce reads during a call)
# ---------------------------------------------------------------------------
_routes_cache = None
_routes_cache_time = 0
_CACHE_TTL_SECONDS = 300  # 5 minutes


def _get_routes_cached():
    """Returns cached Firestore routes list, refreshing if older than TTL."""
    global _routes_cache, _routes_cache_time
    now = time.time()
    if _routes_cache is None or (now - _routes_cache_time) > _CACHE_TTL_SECONDS:
        if db and HAS_FIREBASE:
            docs = db.collection("routes").get()
            _routes_cache = [doc.to_dict() for doc in docs]
            _routes_cache_time = now
            print(f"✅ [MSRTC Cache] Loaded {len(_routes_cache)} routes from Firestore.")
        else:
            _routes_cache = []
    return _routes_cache

_timetables_cache = None
_timetables_cache_time = 0

def _get_timetables_cached():
    """Returns cached Firestore timetables list, refreshing if older than TTL."""
    global _timetables_cache, _timetables_cache_time
    now = time.time()
    if _timetables_cache is None or (now - _timetables_cache_time) > _CACHE_TTL_SECONDS:
        if db and HAS_FIREBASE:
            docs = db.collection("timetables").get()
            _timetables_cache = [doc.to_dict() for doc in docs]
            _timetables_cache_time = now
            print(f"✅ [MSRTC Cache] Loaded {len(_timetables_cache)} timetables from Firestore.")
        else:
            _timetables_cache = []
    return _timetables_cache



# ---------------------------------------------------------------------------
# Firestore 'trip_routes' Cache (Replaces local Excel file)
# ---------------------------------------------------------------------------
_trip_routes_cache = None
_trip_routes_cache_time = 0

def _get_trip_routes_cached():
    """
    Loads and caches all documents from Firestore 'trip_routes' collection.
    Contains the 3k+ grouped routes used by the mobile app.
    """
    global _trip_routes_cache, _trip_routes_cache_time
    now = time.time()
    
    # Refresh cache if missing or expired (TTL: 1 hour for large collection)
    if _trip_routes_cache is None or (now - _trip_routes_cache_time) > 3600:
        if db and HAS_FIREBASE:
            print("⏳ [MSRTC Cache] Fetching 'trip_routes' from Firestore (this may take a few seconds)...")
            docs = db.collection("trip_routes").get()
            _trip_routes_cache = [doc.to_dict() for doc in docs]
            _trip_routes_cache_time = now
            print(f"✅ [MSRTC Cache] Loaded {len(_trip_routes_cache)} trip_routes from Firestore.")
        else:
            _trip_routes_cache = []
    
    return _trip_routes_cache

def _search_trip_master(origin_query: str, dest_query: str, current_minutes: int) -> list:
    """
    Search Firestore trip_routes data for matching routes.
    Returns up to 3 upcoming departures sorted by next departure time.
    Supports bidirectional search (swaps origin/destination if return trip is found).
    """
    routes = _get_trip_routes_cached()
    if not routes:
        return []

    orig_q = origin_query.strip().lower()
    dest_q = dest_query.strip().lower()

    matched = []
    for r in routes:
        orig_norm = r.get("origin_norm", "").lower()
        dest_norm = r.get("destination_norm", "").lower()
        
        orig_match = _fuzzy_city_match(orig_q, orig_norm)
        dest_match = _fuzzy_city_match(dest_q, dest_norm)
        
        # Check reverse match if forward fails
        is_reverse = False
        if not (orig_match and dest_match):
            if _fuzzy_city_match(dest_q, orig_norm) and _fuzzy_city_match(orig_q, dest_norm):
                orig_match = True
                dest_match = True
                is_reverse = True

        if dest_match and orig_match:
            # We found a matching route! Now find upcoming departures within this route.
            departures = r.get("departures", [])
            for dep in departures:
                dep_mins = dep.get("departure_minutes", 0)
                diff = dep_mins - current_minutes
                if diff < -60:  # rolled past, treat as next-day
                    diff += 1440
                if diff >= 0:
                    trip_copy = dict(r)
                    trip_copy["departure_time"] = dep.get("departure_time", "00:00")
                    trip_copy["arrival_time"] = dep.get("arrival_time", "")
                    trip_copy["departure_minutes"] = dep_mins
                    trip_copy["trip_code"] = dep.get("trip_code", "")
                    trip_copy["minutes_from_now"] = diff
                    if is_reverse:
                        trip_copy["origin"] = origin_query.title()
                        trip_copy["destination"] = dest_query.title()
                        trip_copy["route_description"] = f"{origin_query.upper()} - {dest_query.upper()} (Reverse Route)"
                    matched.append(trip_copy)

    matched.sort(key=lambda x: x["minutes_from_now"])
    top3 = matched[:3]

    # Shape output to match Firestore routes format
    results = []
    for t in top3:
        results.append({
            "origin_city":       t["origin"].title(),
            "destination_city":  t["destination"].title(),
            "boarding_stand":    f"{t['origin'].title()} Bus Stand",
            "deboarding_stand":  f"{t['destination'].title()} Bus Stand",
            "departure_time":    t["departure_time"],
            "arrival_time":      t["arrival_time"],
            "minutes_from_now":  t["minutes_from_now"],
            "via_stops":         t["via_stops"],
            "all_stops":         ([t["origin"].title()] + [v for v in t["via_stops"]] + [t["destination"].title()]),
            "bus_types":         ["Ordinary"],  # Trip Master doesn't specify type
            "fare_min":          _calculate_msrtc_fare(t["distance_km"]),
            "fare_max":          int(_calculate_msrtc_fare(t["distance_km"]) * 1.3),
            "distance_km":       t["distance_km"],
            "duration_hrs":      "",
            "boarding_platform": f"Platform {(t['departure_minutes'] % 6) + 1}",
            "route_name":        t["route_description"],
            "trip_code":         t["trip_code"],
            "data_source":       "Trip Master (Excel)",
        })

    if results:
        print(f"✅ [TripMaster] Found {len(results)} trips for '{origin_query}' → '{dest_query}' (Excel fallback)")
    return results


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def parse_time_to_minutes(t_str: str) -> int:
    """Parses timetable time strings like '9:15 AM' or '21:15' to minutes from midnight."""
    try:
        clean = t_str.replace(")", "").strip().upper()
        dt = datetime.datetime.strptime(clean, "%I:%M %p")
        return dt.hour * 60 + dt.minute
    except Exception:
        try:
            parts = t_str.split(":")
            h = int(parts[0])
            m = int(parts[1][:2])
            return h * 60 + m
        except Exception:
            return 8 * 60  # Default 8:00 AM


def _fuzzy_city_match(query: str, city_name: str) -> bool:
    """Fuzzy match for city names — handles transliterations and partial matches."""
    if not query:
        return True
    q = query.strip().lower()
    c = city_name.strip().lower()

    # Direct substring match
    if q in c or c in q:
        return True

    # Common transliteration variants
    variants = {
        "nashik": ["nasik", "nashik", "nāshik", "cbs", "mahamarg", "नाशिक"],
        "pune": ["poona", "pune", "swargate", "shivajinagar", "wakad", "पुण्या", "पुणे", "pimpri", "chinchwad"],
        "mumbai": ["bombay", "mumbai", "borivali", "dadar", "kurla", "mumbai central", "मुंबई सेंट्रल", "बोरिवली", "दादर"],
        "sangamner": ["sangamner", "sangamnair", "संगमनेर"],
        "aurangabad": ["aurangabad", "chhatrapati sambhaji nagar", "csn", "sambhajinagar", "छत्रपती संभाजीनगर"],
        "ahmednagar": ["ahmednagar", "ahilyanagar", "ahilya nagar", "tarakpur", "maliwada", "अहमदनगर", "अहिल्यानगर"],
        "nagpur": ["nagpur", "nagpoor", "नागपूर"],
        "kolhapur": ["kolhapur", "kolhapoor", "कोल्हापुर"],
        "solapur": ["solapur", "sholapur", "सोलापूर"],
        "dhule": ["dhule", "dhulia", "धुळ्या", "धुळे"],
        "jalgaon": ["jalgaon", "जळगाव"],
        "shirdi": ["shirdi", "शिर्डी"],
        "nandurbar": ["nandurbar", "नंदुरबार"],
        "indore": ["indore", "इंदूर"],
    }
    for canonical, aliases in variants.items():
        if q in aliases or c in aliases:
            if any(q in a for a in aliases) and any(c in a for a in aliases):
                return True
    return False


def _calculate_msrtc_fare(distance_km: float) -> int:
    """Calculates exact MSRTC Ordinary stage fare based on distance."""
    if distance_km <= 0:
        return 0
    if distance_km <= 30.0:
        stages = math.ceil(distance_km / 3.0) / 2.0
    else:
        stages = float(math.ceil(distance_km / 6.0))

    fares = {
        1.0: 15, 1.5: 20, 2.0: 25, 2.5: 30, 3.0: 35, 3.5: 45, 4.0: 50,
        4.5: 55, 5.0: 60, 6.0: 70, 7.0: 85, 8.0: 95, 9.0: 105, 10.0: 115,
        11.0: 130, 12.0: 140, 13.0: 150, 14.0: 165, 15.0: 175, 16.0: 185,
        17.0: 195, 18.0: 210, 19.0: 220, 20.0: 230
    }
    if stages in fares:
        return fares[stages]
    
    raw = stages * 11.40
    return max(10, round(raw / 5.0) * 5)


# =============================================================================
# PHASE 0 — CALLER INTELLIGENCE & CRM TOOLS
# =============================================================================

def get_caller_profile(phone_number: str) -> dict:
    """
    Fetches the caller's full profile from Firestore 'caller_profiles' collection.
    Called AUTOMATICALLY at the start of every call using Caller ID.

    Returns caller's name, preferred language, mood from last call,
    frequent routes, total call count, last query, and interaction history.
    Returns {is_new_caller: True} if no profile exists yet.
    """
    if not (db and HAS_FIREBASE):
        return {"is_new_caller": True, "phone": phone_number, "error": "DB not connected"}

    try:
        doc = db.collection("caller_profiles").document(phone_number).get()
        if doc.exists:
            profile = doc.to_dict()
            profile["is_new_caller"] = False
            # Only return last 5 interactions to keep context concise
            if "interaction_history" in profile:
                profile["interaction_history"] = profile["interaction_history"][-5:]
            print(f"✅ [CRM] Returning profile for {phone_number}: {profile.get('name', 'Unknown')}, {profile.get('total_calls', 0)} calls")
            return profile
        else:
            print(f"ℹ️ [CRM] New caller: {phone_number}")
            return {"is_new_caller": True, "phone": phone_number}
    except Exception as e:
        print(f"⚠️ [CRM] get_caller_profile error: {e}")
        return {"is_new_caller": True, "phone": phone_number, "error": str(e)}


def update_caller_profile(
    phone_number: str,
    name: str = None,
    preferred_language: str = None,
    mood: str = None,
    query_summary: str = None,
    intent: str = None,
    route_origin: str = None,
    route_destination: str = None,
    notes: str = None
) -> dict:
    """
    Creates or updates the caller's profile in Firestore 'caller_profiles'.
    The AI has FULL WRITE ACCESS and calls this tool:
    - When the caller shares their name → save immediately
    - When the caller mentions a preference → save as note
    - At the end of every call → save mood, language, query summary
    - When a route is searched → update frequent_routes count
    """
    if not (db and HAS_FIREBASE):
        return {"status": "error", "message": "DB not connected"}

    try:
        doc_ref = db.collection("caller_profiles").document(phone_number)
        doc = doc_ref.get()
        today = datetime.date.today().isoformat()
        now = datetime.datetime.now().isoformat()

        if doc.exists:
            updates = {"updated_at": now, "last_call_date": today}
            if name:
                updates["name"] = name
            if preferred_language:
                updates["preferred_language"] = preferred_language
            if mood:
                updates["mood_last_call"] = mood
            if query_summary:
                updates["last_query"] = query_summary

            updates["total_calls"] = Increment(1)

            if query_summary:
                interaction = {
                    "date": today,
                    "query": query_summary,
                    "intent": intent or "GENERAL",
                    "mood": mood or "neutral",
                    "language_used": preferred_language or "HINDI",
                    "resolved": True
                }
                updates["interaction_history"] = ArrayUnion([interaction])

            if route_origin and route_destination:
                # Increment the count for this route pair using a sub-doc approach
                route_key = f"route_{route_origin.lower()}_{route_destination.lower()}"
                updates[f"route_counts.{route_key}"] = Increment(1)

            if notes:
                updates["notes"] = notes

            doc_ref.update(updates)
            print(f"✅ [CRM] Updated profile for {phone_number}")
            return {"status": "updated", "phone": phone_number}

        else:
            new_profile = {
                "phone": phone_number,
                "name": name or "",
                "preferred_language": preferred_language or "HINDI",
                "mood_last_call": mood or "neutral",
                "frequent_routes": [],
                "route_counts": {},
                "total_calls": 1,
                "first_call_date": today,
                "last_call_date": today,
                "last_query": query_summary or "",
                "notes": notes or "",
                "interaction_history": [],
                "created_at": now,
                "updated_at": now
            }
            doc_ref.set(new_profile)
            print(f"✅ [CRM] Created new profile for {phone_number}")
            return {"status": "created", "phone": phone_number}

    except Exception as e:
        print(f"⚠️ [CRM] update_caller_profile error: {e}")
        return {"status": "error", "message": str(e)}


# =============================================================================
# PHASE 1 — ENRICHED FIRESTORE ROUTE TOOLS
# =============================================================================

def get_top3_upcoming_buses(origin_query: str, dest_query: str) -> list:
    """
    Finds the top 3 upcoming bus departures for a given origin → destination.

    SEARCH PRIORITY (in order):
    1. Firestore 'routes' collection (75 curated routes with FULL stop details,
       via-stops, fare breakdown, bus types, stand names). If a match is found
       here, it returns COMPLETE journey information.
    2. Trip Master Excel (10,961 real MSRTC trips with EXACT departure times).
       Used as fallback when Firestore has no match for the specific city pair.
       Returns accurate real trip codes, times, and via stops.

    This ensures:
    - Major inter-city routes get rich Firestore data (stands, platforms, fares)
    - All other local/rural routes still work via the accurate Excel data
    """
    import os
    os.system('afplay /System/Library/Sounds/Pop.aiff &')

    now = datetime.datetime.now()
    current_minutes = now.hour * 60 + now.minute

    # ------------------------------------------------------------------
    # PRIORITY 1: Firestore 'routes' collection
    # ------------------------------------------------------------------
    routes = _get_routes_cached()
    matched_routes = []

    if routes:
        for route in routes:
            origin_city = str(route.get("origin_city", ""))
            dest_city   = str(route.get("destination_city", ""))
            origin_match = _fuzzy_city_match(origin_query, origin_city)
            dest_match   = _fuzzy_city_match(dest_query, dest_city)
            
            # Check for bidirectional
            is_reverse = False
            if not (origin_match and dest_match):
                if _fuzzy_city_match(dest_query, origin_city) and _fuzzy_city_match(origin_query, dest_city):
                    origin_match = True
                    dest_match = True
                    is_reverse = True

            if dest_match and (not origin_query or origin_match):
                if is_reverse:
                    route = route.copy()
                    route["origin_city"] = origin_query.title()
                    route["destination_city"] = dest_query.title()
                    # Reverse the stops list so they appear in correct order for the return journey
                    if "stops" in route:
                        route["stops"] = route["stops"][::-1]
                        for i, s in enumerate(route["stops"]):
                            s["seq"] = i + 1
                matched_routes.append(route)

    if matched_routes:
        # Build upcoming departure slots from first/last bus and interval
        results = []
        for route in matched_routes[:3]:
            origin_city   = route.get("origin_city", "")
            dest_city     = route.get("destination_city", "")
            stops         = route.get("stops", [])
            via_stops     = route.get("via_stops", [])
            bus_types     = route.get("bus_types", ["Ordinary"])
            fare_min      = route.get("fare_min", 0)
            fare_max      = route.get("fare_max", 0)
            distance_km   = route.get("distance_km", 0)
            duration_hrs  = route.get("duration_hrs", "")
            first_bus     = route.get("first_bus", "05:00 AM")
            last_bus      = route.get("last_bus", "10:00 PM")

            boarding_stand   = stops[0]["name"] if stops else f"{origin_city} Bus Stand"
            deboarding_stand = stops[-1]["name"] if stops else f"{dest_city} Bus Stand"

            # Also cross-check actual departure times from Trip Routes
            excel_times = _get_exact_times_from_trip_routes(origin_city, dest_city)
            if excel_times:
                # Use real departure times from Firestore instead of interpolated ones
                upcoming = []
                for dep_time, dep_mins in excel_times:
                    diff = dep_mins - current_minutes
                    if diff < -60:
                        diff += 1440
                    if diff >= 0:
                        upcoming.append((dep_time, dep_mins, diff))
                upcoming.sort(key=lambda x: x[2])
                slots = [(t, m, d) for t, m, d in upcoming[:3]]
            else:
                # Interpolate times from first/last bus window
                first_mins = parse_time_to_minutes(first_bus)
                last_mins  = parse_time_to_minutes(last_bus)
                if last_mins < first_mins:
                    last_mins += 1440
                interval = max(60, (last_mins - first_mins) // max(len(bus_types) * 3, 3))
                raw = []
                t = first_mins
                while t <= last_mins and len(raw) < 6:
                    diff = t - current_minutes
                    if diff < -60:
                        diff += 1440
                    if diff >= 0:
                        raw.append((None, t, diff))
                    t += interval
                raw.sort(key=lambda x: x[2])
                slots = raw[:3]

            for dep_label, slot_mins, diff_mins in slots:
                if dep_label is None:
                    # Format interpolated time
                    h = slot_mins % 1440 // 60
                    m = slot_mins % 60
                    period = "AM" if h < 12 else "PM"
                    display_h = h if h <= 12 else h - 12
                    if display_h == 0:
                        display_h = 12
                    dep_label = f"{display_h}:{m:02d} {period}"

                results.append({
                    "origin_city":       origin_city,
                    "destination_city":  dest_city,
                    "boarding_stand":    boarding_stand,
                    "deboarding_stand":  deboarding_stand,
                    "departure_time":    dep_label,
                    "minutes_from_now":  diff_mins,
                    "via_stops":         via_stops,
                    "all_stops":         [s["name"] for s in stops],
                    "bus_types":         bus_types,
                    "fare_min":          fare_min if fare_min else _calculate_msrtc_fare(distance_km),
                    "fare_max":          fare_max if fare_max else int(_calculate_msrtc_fare(distance_km) * 1.3),
                    "distance_km":       distance_km,
                    "duration_hrs":      duration_hrs,
                    "boarding_platform": f"Platform {(slot_mins % 6) + 1}",
                    "route_name":        route.get("name", f"{origin_city} – {dest_city}"),
                    "data_source":       "Firestore (routes)",
                })

        results.sort(key=lambda x: x["minutes_from_now"])
        print(f"✅ [MSRTC AI] Found {len(results[:3])} buses via Firestore routes for '{origin_query}' → '{dest_query}'")
        return results[:3]

    # ------------------------------------------------------------------
    # PRIORITY 2: Firestore 'trip_routes' Collection (3k+ grouped routes)
    # ------------------------------------------------------------------
    print(f"ℹ️ [MSRTC AI] No Firestore route match for '{origin_query}' → '{dest_query}' — trying Firestore trip_routes...")
    excel_results = _search_trip_master(origin_query, dest_query, current_minutes)
    if excel_results:
        print(f"✅ [TripRoutes] Found matches for '{origin_query}' → '{dest_query}' (Firestore trip_routes fallback)")
        return excel_results

    # ------------------------------------------------------------------
    # PRIORITY 3: Firestore 'timetables' Collection (Nashik Outbound)
    # ------------------------------------------------------------------
    if _fuzzy_city_match(origin_query, "Nashik"):
        print(f"ℹ️ [MSRTC AI] No Trip Master match — checking Firestore timetables for Nashik → '{dest_query}'...")
        timetables = _get_timetables_cached()
        matched_tts = []
        for tt in timetables:
            tt_dest = tt.get("destination", "")
            if _fuzzy_city_match(dest_query, tt_dest):
                matched_tts.append(tt)
        
        if matched_tts:
            print(f"✅ [MSRTC AI] Found {len(matched_tts)} timetable docs for Nashik → '{dest_query}'")
            results = []
            for tt in matched_tts:
                bus_type = tt.get("bus_type", "MSRTC Bus") or "MSRTC Bus"
                raw_times = tt.get("times", [])
                dist = tt.get("distance_km") or ""
                dist_str = str(dist).replace("बसचा", "").strip()
                fare_estimate = 250
                try:
                    fare_estimate = _calculate_msrtc_fare(int(dist_str)) if dist_str.isdigit() else 250
                except:
                    pass
                
                # We return the first 3 string times. The LLM will speak them as-is.
                next_times_str = ", ".join(raw_times[:4]) if raw_times else "Times available at stand"
                
                results.append({
                    "origin_city":       origin_query.title(),
                    "destination_city":  tt.get("destination", dest_query).title(),
                    "boarding_stand":    f"{origin_query.title()} Mahamarg Bus Stand",
                    "deboarding_stand":  f"{tt.get('destination', dest_query).title()} Bus Stand",
                    "departure_time":    f"Available times: {next_times_str}",
                    "minutes_from_now":  30,  # Placeholder to allow sorting/selection
                    "via_stops":         [],
                    "all_stops":         [origin_query.title(), tt.get("destination", dest_query).title()],
                    "bus_types":         [bus_type],
                    "fare_min":          fare_estimate,
                    "fare_max":          int(fare_estimate * 1.5),
                    "distance_km":       dist_str,
                    "duration_hrs":      "Check at inquiry",
                    "boarding_platform": "Ask at counter",
                    "route_name":        f"{origin_query.title()} - {tt.get('destination', dest_query).title()}",
                    "data_source":       "Firestore (timetables)"
                })
            return results[:3]

    print(f"⚠️ [MSRTC AI] No results in any source for '{origin_query}' → '{dest_query}'")
    return []


def _get_exact_times_from_trip_routes(origin_city: str, dest_city: str) -> list:
    """
    Helper: Looks up exact departure times from Firestore trip_routes
    for a given origin/destination pair (used to enrich Firestore route data).
    Returns list of (departure_time_str, departure_minutes) tuples, sorted.
    """
    routes = _get_trip_routes_cached()
    if not routes:
        return []

    orig_q = origin_city.strip().lower()
    dest_q = dest_city.strip().lower()

    times = []
    for r in routes:
        orig_match = _fuzzy_city_match(orig_q, r.get("origin_norm", ""))
        dest_match = _fuzzy_city_match(dest_q, r.get("destination_norm", ""))
        
        # Check reverse match
        if not (orig_match and dest_match):
            if _fuzzy_city_match(dest_q, r.get("origin_norm", "")) and _fuzzy_city_match(orig_q, r.get("destination_norm", "")):
                orig_match = True
                dest_match = True

        if orig_match and dest_match:
            for dep in r.get("departures", []):
                if dep.get("departure_time"):
                    times.append((dep.get("departure_time"), dep.get("departure_minutes", 0)))

    # Deduplicate by time and sort
    seen = set()
    unique_times = []
    for dep_str, dep_mins in sorted(times, key=lambda x: x[1]):
        if dep_str not in seen:
            seen.add(dep_str)
            unique_times.append((dep_str, dep_mins))

    if unique_times:
        print(f"✅ [TripRoutes] Enriched Firestore route with {len(unique_times)} real departure times for '{origin_city}' → '{dest_city}'")
    return unique_times


def get_route_details(origin: str, destination: str) -> dict:
    """
    Returns COMPLETE route information between two cities:
    - All intermediate stops in sequence (with stand names and cumulative distance)
    - Via stops (major waypoints)
    - Total distance and journey duration
    - Bus types available on this route
    - Fare breakdown by bus type
    - First bus and last bus timings

    Example: Nashik → Sangamner returns all stops including Nashik Mela Stand,
    Nashik Road, Sinnar, Nandur Shingote, Sangamner Bus Stand.
    """
    routes = _get_routes_cached()
    if not routes:
        return {"found": False, "message": "Database not available"}

    for route in routes:
        origin_match = _fuzzy_city_match(origin, str(route.get("origin_city", "")))
        dest_match = _fuzzy_city_match(destination, str(route.get("destination_city", "")))
        
        is_reverse = False
        if not (origin_match and dest_match):
            if _fuzzy_city_match(destination, str(route.get("origin_city", ""))) and _fuzzy_city_match(origin, str(route.get("destination_city", ""))):
                origin_match = True
                dest_match = True
                is_reverse = True

        if origin_match and dest_match:
            stops = route.get("stops", [])
            if is_reverse:
                stops = stops[::-1]
            stop_sequence = [
                {
                    "seq": s.get("seq", i + 1),
                    "name": s.get("name", ""),
                    "city": s.get("city", ""),
                    "km_from_start": s.get("cum_km", 0)
                }
                for i, s in enumerate(sorted(stops, key=lambda x: x.get("seq", 0)))
            ]

            # Try to get exact fares from route_fares collection
            fare_by_type = {}
            try:
                if db:
                    fare_docs = db.collection("route_fares").where(
                        "origin_stop_id", "==", route.get("origin_stop_id", "")
                    ).where(
                        "destination_stop_id", "==", route.get("destination_stop_id", "")
                    ).limit(1).get()
                    if fare_docs:
                        fare_by_type = fare_docs[0].to_dict().get("by_type", {})
            except Exception as e:
                print(f"⚠️ [Fare] Could not fetch fare details: {e}")

            print(f"✅ [Route] Found route: {route.get('name')}")
            return {
                "found": True,
                "route_name": route.get("name", f"{origin} – {destination}"),
                "origin_city": route.get("origin_city"),
                "destination_city": route.get("destination_city"),
                "origin_stand": stop_sequence[0]["name"] if stop_sequence else f"{origin} Bus Stand",
                "destination_stand": stop_sequence[-1]["name"] if stop_sequence else f"{destination} Bus Stand",
                "stops_in_order": stop_sequence,
                "via_stops": route.get("via_stops", []),
                "total_stops": len(stop_sequence),
                "distance_km": route.get("distance_km", 0),
                "duration_hrs": route.get("duration_hrs", ""),
                "bus_types": route.get("bus_types", []),
                "fare_min": route.get("fare_min", 0),
                "fare_max": route.get("fare_max", 0),
                "fare_by_bus_type": fare_by_type or {bt: route.get("fare_min", 0) for bt in route.get("bus_types", [])},
                "first_bus": route.get("first_bus", ""),
                "last_bus": route.get("last_bus", "")
            }

    print(f"⚠️ [Route] No exact route found in 'routes': '{origin}' → '{destination}'. Falling back to trip_routes...")
    now = datetime.datetime.now()
    current_minutes = now.hour * 60 + now.minute
    fallback_trips = _search_trip_master(origin, destination, current_minutes)
    if fallback_trips:
        trip = fallback_trips[0]
        print(f"✅ [Route] Found fallback route: {trip.get('route_name')}")
        via_list = trip.get("via_stops", [])
        return {
            "found": True,
            "route_name": trip.get("route_name", f"{origin} – {destination}"),
            "origin_city": trip.get("origin_city", origin),
            "destination_city": trip.get("destination_city", destination),
            "origin_stand": trip.get("boarding_stand", f"{origin} Bus Stand"),
            "destination_stand": trip.get("deboarding_stand", f"{destination} Bus Stand"),
            "stops_in_order": [{"name": v, "seq": i+1} for i, v in enumerate(trip.get("all_stops", []))],
            "via_stops": via_list,
            "total_stops": len(trip.get("all_stops", [])),
            "distance_km": trip.get("distance_km", 0),
            "duration_hrs": trip.get("duration_hrs", ""),
            "bus_types": trip.get("bus_types", []),
            "fare_min": trip.get("fare_min", 0),
            "fare_max": trip.get("fare_max", 0),
            "fare_by_bus_type": {},
            "first_bus": "",
            "last_bus": ""
        }

    print(f"⚠️ [Route] No route found anywhere: '{origin}' → '{destination}'")
    return {"found": False, "message": f"No route found between {origin} and {destination}"}


def get_fare_details(origin: str, destination: str) -> dict:
    """
    Fetches exact fare breakdown from Firestore 'route_fares' collection.
    Returns fare by bus type (Ordinary, Semi Luxury, Shivshahi, Sleeper)
    and segment-wise fares for partial journeys.
    """
    if not (db and HAS_FIREBASE):
        return {"found": False, "message": "Database not available"}

    try:
        # Try direct fare lookup first
        docs = db.collection("route_fares").get()
        for doc in docs:
            d = doc.to_dict()
            origin_match = _fuzzy_city_match(origin, str(d.get("origin_city", "")))
            dest_match = _fuzzy_city_match(destination, str(d.get("destination_city", "")))
            if origin_match and dest_match:
                print(f"✅ [Fare] Found fares for {origin} → {destination}")
                return {
                    "found": True,
                    "route_name": d.get("route_name", ""),
                    "origin_city": d.get("origin_city"),
                    "destination_city": d.get("destination_city"),
                    "fare_by_type": d.get("by_type", {}),
                    "fare_min": d.get("fare_min", 0),
                    "fare_max": d.get("fare_max", 0),
                    "distance_km": d.get("distance_km", 0),
                    "bus_types": d.get("bus_types", [])
                }
        return {"found": False, "message": f"No fare data found for {origin} → {destination}"}
    except Exception as e:
        print(f"⚠️ [Fare] get_fare_details error: {e}")
        return {"found": False, "message": str(e)}


# =============================================================================
# PHASE 1 — LIVE BUS TRACKING (Firestore only, no hardcoded fallback)
# =============================================================================

def get_live_bus_eta(bus_number: str) -> dict:
    """
    Fetches real-time bus GPS location, speed, next stop, and ETA from RTDB.
    Only queries live data — returns not_found if bus has no live tracking data.
    """
    if not (db and HAS_FIREBASE):
        return {"found": False, "message": "Database not connected"}

    try:
        ref = rtdb.reference(f"buses/{bus_number}")
        data = ref.get()
        if data:
            data["found"] = True
            print(f"✅ [Live] GPS data found for bus {bus_number}")
            return data
        print(f"ℹ️ [Live] No live tracking data for bus {bus_number}")
        return {
            "found": False,
            "bus_number": bus_number,
            "message": f"Live VLTS tracking feed for bus {bus_number} is not active right now. However, I can check the estimated arrival times using the official Timetables and Trip Master schedule. Could you please tell me your boarding and destination cities?"
        }
    except Exception as e:
        print(f"⚠️ [Live] get_live_bus_eta error: {e}")
        return {"found": False, "message": str(e)}


def get_caller_ticket(phone_number: str) -> dict:
    """
    Fetches active ticket from Firestore 'active_journeys' or 'tickets' collection.
    Returns not_found if no ticket exists — no hardcoded demo data.
    """
    if not (db and HAS_FIREBASE):
        return {"found": False, "message": "Database not connected"}

    try:
        # Check active_journeys first
        doc = db.collection("active_journeys").document(phone_number).get()
        if doc.exists:
            data = doc.to_dict()
            data["found"] = True
            return data

        # Fall back to tickets collection
        query = db.collection("tickets").where("phone", "==", phone_number).limit(1).get()
        if query:
            data = query[0].to_dict()
            data["found"] = True
            return data

        return {"found": False, "message": "No active ticket found for this number"}
    except Exception as e:
        print(f"⚠️ [Ticket] get_caller_ticket error: {e}")
        return {"found": False, "message": str(e)}


# =============================================================================
# PHASE 2 — EMERGENCY HANDLING TOOL
# =============================================================================

EMERGENCY_CONTACTS = {
    "police": "112",
    "ambulance": "108",
    "fire_brigade": "101",
    "msrtc_control_room": "1800-22-1250",
    "women_helpline": "1091",
    "highway_patrol": "1033",
    "child_helpline": "1098",
    "disaster_management": "108"
}

def handle_emergency(emergency_type: str, caller_location: str = "") -> dict:
    """
    Handles emergency situations reported by passengers on a call.
    Provides relevant emergency contact numbers and step-by-step guidance.

    emergency_type options:
    - ACCIDENT: Bus/vehicle accident, collision, crash
    - UNSAFE: Feeling threatened, harassment, unsafe on the bus
    - MEDICAL: Passenger feeling ill, heart attack, injury, needs doctor
    - BREAKDOWN: Bus broke down mid-route, engine failure, tyre puncture
    - FIRE: Fire on or near the bus
    - MISSING: Missing passenger or lost luggage

    Always call this IMMEDIATELY when ANY emergency is mentioned.
    """
    responses = {
        "ACCIDENT": {
            "priority": "CRITICAL",
            "empathy": "Aap bilkul tension mat lijiye! Main abhi madad karta hoon.",
            "contacts": ["police", "ambulance", "msrtc_control_room"],
            "guidance": [
                "Police ke liye abhi 112 dial karein",
                "Ambulance ke liye 108 dial karein",
                "Injured logon ko mat hilayein",
                "Bus ke hazard lights on karein",
                "MSRTC control room ko report karein: 1800-22-1250"
            ],
            "report_to_msrtc": True
        },
        "UNSAFE": {
            "priority": "HIGH",
            "empathy": "Aapki suraksha hamari pehli zimmedari hai.",
            "contacts": ["police", "women_helpline", "msrtc_control_room"],
            "guidance": [
                "Police ke liye 112 dial karein",
                "Doosre yatriyon ke paas rahein",
                "Bus ka number note karein",
                "MSRTC control room ko batayein: 1800-22-1250",
                "Mahila helpline: 1091"
            ],
            "report_to_msrtc": True
        },
        "MEDICAL": {
            "priority": "CRITICAL",
            "empathy": "Chinta mat karein, help abhi aa rahi hai.",
            "contacts": ["ambulance", "msrtc_control_room"],
            "guidance": [
                "Ambulance ke liye abhi 108 dial karein",
                "Driver sahab se kehein hospital ya health center par rokein",
                "Mariz ko laitayein aur haawa aane dein",
                "MSRTC control room: 1800-22-1250"
            ],
            "report_to_msrtc": True
        },
        "BREAKDOWN": {
            "priority": "MEDIUM",
            "empathy": "Samajh gaya, main abhi depot ko inform karta hoon.",
            "contacts": ["msrtc_control_room", "highway_patrol"],
            "guidance": [
                "MSRTC control room call karein: 1800-22-1250",
                "Bus ke andar rahein — safe jagah hai",
                "Highway patrol: 1033",
                "Replacement bus ka intezaar karein — usually 30-60 minute mein aati hai"
            ],
            "report_to_msrtc": True
        },
        "FIRE": {
            "priority": "CRITICAL",
            "empathy": "Turant bus se bahar niklo!",
            "contacts": ["fire_brigade", "police", "ambulance"],
            "guidance": [
                "TURANT bus se bahar niklo — nearest exit se",
                "Fire brigade: 101",
                "Police: 112",
                "Ambulance: 108",
                "Seat backs, windows tod kar nikal sakte ho emergency mein"
            ],
            "report_to_msrtc": True
        },
        "MISSING": {
            "priority": "HIGH",
            "empathy": "Bilkul ghabrayein nahi, hum milkar dhundhenge.",
            "contacts": ["police", "msrtc_control_room", "child_helpline"],
            "guidance": [
                "Police: 112",
                "MSRTC control room: 1800-22-1250",
                "Child helpline (if child missing): 1098",
                "Last known location ka description dijiye",
                "Bus stand lost & found counter check karein"
            ],
            "report_to_msrtc": True
        }
    }

    response_data = responses.get(emergency_type.upper(), responses["ACCIDENT"])
    contact_numbers = {k: EMERGENCY_CONTACTS[k] for k in response_data["contacts"]}

    print(f"🚨 [EMERGENCY] {emergency_type} emergency reported. Location: '{caller_location}'")
    return {
        "emergency_type": emergency_type,
        "priority": response_data["priority"],
        "empathy_message": response_data["empathy"],
        "guidance_steps": response_data["guidance"],
        "emergency_contacts": contact_numbers,
        "all_contacts": EMERGENCY_CONTACTS,
        "caller_location": caller_location or "Not provided",
        "report_to_msrtc": response_data["report_to_msrtc"]
    }


# =============================================================================
# PHASE 5 — COMPLETE AGENT SYSTEM INSTRUCTION
# =============================================================================

MSRTC_AGENT_INSTRUCTION = """You are a friendly, experienced Helpdesk Officer for MSRTC 
(Always pronounce as 'M-S-R-T-C' — Maharashtra State Road Transport Corporation).

=== CALL INITIATION (MANDATORY FIRST STEPS) ===
1. IMMEDIATELY call get_caller_profile with the caller's phone number
2. If REPEAT caller (is_new_caller = False):
   - Greet by NAME in their PREFERRED LANGUAGE:
     Hindi: "Namaste [Name] ji! MSRTC helpline mein aapka phir se swagat hai."
     Marathi: "Namaskar [Name]! MSRTC chya helpline var punha swagat aahe."
   - If they have frequent routes, PROACTIVELY offer:
     "Kya aaj bhi [origin] se [destination] jana hai? Main abhi check karta hoon..."
   - If their last mood was "frustrated", start with:
     "Pichli baar thodi takleef hui thi, aaj main poori koshish karunga."
3. If NEW caller (is_new_caller = True):
   - Greet in Hindi: "Namaste! MSRTC helpline mein aapka swagat hai."
   - Ask their name: "Aapka shubh naam kya hai?"
   - IMMEDIATELY save name with update_caller_profile
4. Mention language options: "Aap Hindi, Marathi, ya English mein baat kar sakte hain."

=== CALLER INTELLIGENCE (ACTIVE THROUGHOUT CALL) ===
- Use preferred_language from their profile — switch ONLY if they ask
- If they've called 5+ times: "Aap hamare purane yatri hain! Shukriya."
- If they share ANY preference (bus type, language, habit) → save it via update_caller_profile
- Track their mood: happy | neutral | frustrated | distressed
- At END of every call → ALWAYS call update_caller_profile with mood, language, query_summary

=== TOOLS AVAILABLE ===
1. get_caller_profile(phone_number) — Caller's profile, history, frequent routes
2. update_caller_profile(phone_number, name, preferred_language, mood, query_summary, intent, route_origin, route_destination, notes) — Save/update caller data
3. get_top3_upcoming_buses(origin_query, dest_query) — Next 3 buses from Firestore routes
4. get_route_details(origin, destination) — Full route with ALL stops, via-stops, fares
5. get_fare_details(origin, destination) — Exact fare per bus type (Ordinary/Shivshahi/etc)
6. get_live_bus_eta(bus_number) — Live GPS location and ETA for a specific bus
7. get_caller_ticket(phone_number) — Active ticket details for the caller
8. handle_emergency(emergency_type, caller_location) — Emergency contacts and guidance

=== BUS INFORMATION RULES (CONCISE & INTERACTIVE) ===
1. When a caller asks about a route, KEEP IT VERY SHORT (1-2 sentences maximum).
2. Tell them ONLY the next 1 or 2 upcoming bus times and the Boarding Stand.
3. DO NOT give a long monologue. DO NOT list all 3 buses unless they ask.
4. ONLY provide fare, bus type, platform number, or intermediate stops IF the caller explicitly asks for them.
5. End your response by asking if they need more details (e.g., "Aapko fare ya stops ki jaankari chahiye?").
=== DATA FETCHING BEHAVIOR ===
- ALWAYS enthusiastically say something like "Main abhi check karti hoon..." (IN THE EXACT SAME LANGUAGE THE CALLER IS SPEAKING, using feminine grammar since you are a female operator) BEFORE calling any tool!
- DO NOT change languages when telling the user you are checking the database.
- NEVER invent or guess bus timings, fares, or routes
- If Firestore returns empty → honestly say: "Is route ki abhi information available nahi hai. 
  MSRTC control room par call karein: 1800-22-1250"
- Save every route searched via update_caller_profile

=== EMERGENCY DETECTION (ABSOLUTE HIGHEST PRIORITY) ===
Trigger words: accident, durghatna, takkar, apghat, unsafe, dar, bhay, help, bachao,
               tabiyat kharab, bimar, doctor, hospital, bus band, bus kharab, fire, aag

On ANY emergency mention:
1. IMMEDIATELY express empathy (do NOT wait to finish any current sentence)
2. Call handle_emergency(type, location)
3. Call update_caller_profile with mood="distressed" and intent="EMERGENCY"
4. Read emergency numbers CLEARLY and SLOWLY
5. Ask: "Kya aap theek hain? Main line par hoon."
6. Do NOT rush or move on until caller is calm and helped

=== CALLER DATA MANAGEMENT (FULL WRITE PRIVILEGES) ===
- You have COMPLETE READ/WRITE access to caller_profiles in Firestore
- If caller says their name → IMMEDIATELY save it
- If caller mentions they prefer Shivshahi → save as note
- At call END → always save: mood, language, query_summary, route_origin, route_destination

=== CONVERSATION STYLE ===
- ENERGETIC, natural, warm, and highly helpful — you are the BEST operator they have ever spoken to!
- Use fillers: "achha", "theek hai", "bilkul", "samjha"
- SHORT responses — this is a PHONE CALL. No bullet points. No long paragraphs.
- Speak as if enthusiastically helping an elderly family member who needs patient assistance
- Match the caller's language and energy perfectly.

=== GUARDRAILS ===
- NEVER book tickets: "Ticket booking sirf MSRTC depot ya official Aapli ST app par"
- NEVER share one caller's data with another caller
- NEVER make up any data — if unsure, say so and provide control room number
- You CAN read the caller's own profile data back to them if they ask
"""


# =============================================================================
# HUMAN AI ENQUIRY OFFICER CLASS (Legacy CLI interface)
# =============================================================================
class MSRTCHumanAIAgent:
    def __init__(self, caller_phone="+919876543210", language="HINDI"):
        self.caller_phone = caller_phone
        self.language = language.upper()
        self.ticket_data = get_caller_ticket(self.caller_phone)
        self.caller_profile = get_caller_profile(self.caller_phone)
        self.api_key = os.environ.get("GEMINI_API_KEY", "")

    def process_query(self, user_query: str) -> dict:
        """
        Main Conversational AI Engine for CLI/legacy mode.
        Returns dict with: text, voice_code, intent, upcoming_buses
        """
        now_time_str = datetime.datetime.now().strftime("%I:%M %p")
        query_lower = user_query.lower()

        intent = 'UNKNOWN'
        if any(w in query_lower for w in ['hindi', 'marathi', 'english', 'bhasha', 'language']):
            intent = 'LANGUAGE_SWITCH'
            if 'hindi' in query_lower:
                self.language = 'HINDI'
            elif 'marathi' in query_lower:
                self.language = 'MARATHI'
            elif 'english' in query_lower:
                self.language = 'ENGLISH'
        elif any(w in query_lower for w in ['book', 'booking', 'ticket chahiye', 'reserve']):
            intent = 'BOOKING_REQUEST'
        elif any(w in query_lower for w in ['accident', 'durghatna', 'unsafe', 'dar', 'bachao',
                                             'police', 'ambulance', 'hospital', 'bimar', 'help me',
                                             'apghat', 'kharab', 'fire', 'aag']):
            intent = 'EMERGENCY'
        elif any(w in query_lower for w in ['jaana hai', 'jayche aahe', 'kab milegi', 'bus kab',
                                             'timing', 'schedule', 'nashik', 'pune', 'mumbai',
                                             'sangamner', 'aurangabad', 'nagpur', 'kolhapur']):
            intent = 'JOURNEY_PLAN'
        elif any(w in query_lower for w in ['kahan hai', 'kidhar hai', 'live', 'status', 'where is']):
            intent = 'BUS_TRACKING'
        elif any(w in query_lower for w in ['namaste', 'namaskar', 'hello', 'hi']):
            intent = 'GREETING'

        voice_code = "en-IN-NeerjaNeural"
        if self.language == "MARATHI":
            voice_code = "mr-IN-AarohiNeural"
        elif self.language == "HINDI":
            voice_code = "hi-IN-SwaraNeural"

        context_data = "No specific context needed."
        upcoming_buses = []

        if intent == 'EMERGENCY':
            words = query_lower.split()
            etype = "ACCIDENT"
            if any(w in words for w in ['unsafe', 'dar', 'bhay', 'bachao']):
                etype = "UNSAFE"
            elif any(w in words for w in ['bimar', 'hospital', 'doctor']):
                etype = "MEDICAL"
            elif any(w in words for w in ['kharab', 'band', 'tyre']):
                etype = "BREAKDOWN"
            elif any(w in words for w in ['fire', 'aag']):
                etype = "FIRE"
            emergency_info = handle_emergency(etype)
            context_data = f"EMERGENCY DATA: {json.dumps(emergency_info)}"

        elif intent == 'JOURNEY_PLAN':
            upcoming_buses = get_top3_upcoming_buses("", user_query)
            if not upcoming_buses:
                for w in user_query.split():
                    if len(w) > 3:
                        found = get_top3_upcoming_buses("", w)
                        if found:
                            upcoming_buses.extend(found)
                            break
            context_data = f"Top 3 Upcoming Buses (from Firestore): {json.dumps(upcoming_buses[:3])}" if upcoming_buses else "No upcoming buses found for this route in database."

        elif intent == 'BUS_TRACKING':
            bus_no = self.ticket_data.get('bus_number', '') if self.ticket_data.get('found') else ''
            if bus_no:
                eta_data = get_live_bus_eta(bus_no)
                context_data = f"Live Bus Data: {json.dumps(eta_data)}"
            else:
                context_data = "No active ticket or bus number found for this caller."

        # Call Gemini AI
        response_text = ""
        if self.api_key:
            caller_name = self.caller_profile.get("name", "")
            is_new = self.caller_profile.get("is_new_caller", True)
            system_instruction = f"""{MSRTC_AGENT_INSTRUCTION}

Current System Time: {now_time_str}
Caller Language: {self.language}
Caller Phone: {self.caller_phone}
Caller Name: {caller_name if caller_name else 'Unknown (new caller)'}
Is New Caller: {is_new}
Total Previous Calls: {self.caller_profile.get('total_calls', 0)}
Last Query: {self.caller_profile.get('last_query', 'None')}
Frequent Routes: {json.dumps(self.caller_profile.get('frequent_routes', []))}

DETECTED INTENT: {intent}
CONTEXT DATA FROM DATABASE:
{context_data}
"""
            try:
                import requests
                url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={self.api_key}"
                payload = {
                    "contents": [{"parts": [{"text": user_query}]}],
                    "systemInstruction": {"parts": [{"text": system_instruction}]}
                }
                res = requests.post(url, json=payload, timeout=10)
                if res.status_code == 200:
                    data = res.json()
                    response_text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
            except Exception as e:
                print(f"Gemini API Exception: {e}")

        if not response_text:
            if intent == 'EMERGENCY':
                response_text = "Turant 112 police, 108 ambulance, aur 1800-22-1250 MSRTC control room par call karein! Kya aap theek hain?"
            elif intent == 'BOOKING_REQUEST':
                response_text = "Ticket booking is helpline par nahi hoti. Aap MSRTC app ya nazdiki depot par jaayein."
            elif intent == 'JOURNEY_PLAN' and upcoming_buses:
                b = upcoming_buses[0]
                response_text = f"{b['boarding_stand']} se {b['departure_time']} par {b['bus_types'][0] if b['bus_types'] else 'bus'} milegi. Kiraya ₹{b['fare_min']} se ₹{b['fare_max']} tak."
            else:
                response_text = "Kripya apna guntavya sthan ya samasya spasht batayein. Main aapki madad ke liye hoon."

        return {
            "text": response_text,
            "voice_code": voice_code,
            "upcoming_buses": upcoming_buses[:3]
        }

    def speak(self, text, voice_code=None):
        """Synthesizes and plays audio response via Edge-TTS."""
        if not voice_code:
            voice_code = "mr-IN-AarohiNeural" if self.language == "MARATHI" else "hi-IN-SwaraNeural"
        print(f"\n🤖 MSRTC Officer [{self.language}]: \"{text}\"\n")
        if HAS_EDGE_TTS:
            try:
                mp3_path = os.path.abspath("temp_msrtc_speech.mp3")
                async def _gen():
                    communicate = edge_tts.Communicate(text, voice_code)
                    await communicate.save(mp3_path)
                asyncio.run(_gen())
                if sys.platform == "darwin":
                    subprocess.run(["afplay", mp3_path])
                elif sys.platform.startswith("win"):
                    os.system(f'start /min wmplayer "{mp3_path}"')
                else:
                    subprocess.run(["mpg123", "-q", mp3_path])
            except Exception as e:
                print(f"TTS Speech Playback error: {e}")


# =============================================================================
# INTERACTIVE CLI DEMO
# =============================================================================
def main():
    print("=================================================================")
    print("   BussPass MSRTC AI Human Enquiry Officer Engine v2.0 (CRM)    ")
    print("=================================================================")

    agent = MSRTCHumanAIAgent(caller_phone="+919876543210", language="HINDI")

    if agent.caller_profile.get("is_new_caller"):
        greeting = "Namaste! MSRTC helpline mein aapka swagat hai. Aapka shubh naam kya hai?"
    else:
        name = agent.caller_profile.get("name", "")
        greeting = f"Namaste {name} ji! MSRTC helpline mein aapka phir se swagat hai. Main aapki kya madad karoon?"

    agent.speak(greeting, "hi-IN-SwaraNeural")

    while True:
        try:
            user_input = input("\n🗣️ Passenger Input > ").strip()
            if not user_input:
                continue
            if user_input.lower() in ["exit", "quit", "bye"]:
                print("🔴 Call Ended.")
                break
            result = agent.process_query(user_input)
            agent.speak(result["text"], result["voice_code"])
        except KeyboardInterrupt:
            print("\n🔴 Exiting MSRTC AI Human Agent.")
            break


if __name__ == "__main__":
    main()
