# BussPass Architecture & Knowledge Base

This document serves as the primary architectural reference for the BussPass application. It must be updated after every major feature addition to provide context and inspiration for future developers and AI agents.

## 1. UI & Aesthetics (Premium Standard)
- **Theme**: We use a premium, calm "Nature/Sage" color palette (soft sage greens, deep charcoal greens, pale mint grays) to provide a relaxing, eye-soothing, and high-end feel. 
- **Typography**: Google Fonts `Inter` for highly readable, crisp typography.
- **Animations**: `flutter_animate` is heavily utilized for micro-interactions, staggered entries, and tactile feedback. Avoid generic, stiff UI.
- **Components**: We prioritize on-screen, accessible elements over hidden navigation drawers (hamburger menus).

## 2. Navigation Architecture
- **Root Routing**: Handled in `main.dart` via `AuthWrapper`. 
- **Unauthenticated**: Routes to `LanguageScreen` (onboarding) -> `AuthScreen` (Google Sign-In).
- **Authenticated**: Routes directly to `DashboardScreen`.
- **Dashboard Structure**: A custom `BottomNavigationBar` using `IndexedStack` to preserve state across 4 main tabs:
  - `HomeTab`: The action center (Where to?, Quick actions).
  - `MapTab`: Full-screen live tracking map.
  - `PassesTab`: Digital tickets.
  - `ProfileTab`: Settings & support.

## 3. Database Architecture (Firestore)
The application uses Firebase Firestore. To support complex operations efficiently, we use flat collections and client-side processing where possible.

### Core Collections
1. **`bus_stops`**: 
   - Stores physical bus stand locations.
   - Used for plotting map markers and searching destinations.

2. **`routes`**:
   - Defines bus lines (e.g., MSRTC-PUN-MUM-AC).
   - Contains metadata (bus type, total distance).
   - **`stops` array**: ordered list of resolved stops with `{stop_id, name, city, lat, lng, seq, cum_km}`. The `lat`/`lng` are exact coordinates and `cum_km` is the distance measured along the corridor from the origin. This lets the map draw an **accurate polyline** that follows the actual road/route corridor through every intermediate stop (instead of a straight origin→destination line), and shows intermediate markers.

3. **`route_stops`** (Planned):
   - The graph structure mapping stops to routes with sequence orders and estimated arrival times.

4. **`route_fares`** (per route):
   - Rich pricing doc: `by_type` = full-route fare per bus type, `segments` = keyed `"{fromStopId}__{toStopId}"` map of stop-pair segments, each with `{from, to, from_stop_id, to_stop_id, from_seq, to_seq, distance_km, by_type}` where `by_type` gives the MSRTC stage-based fare between those two stops for every bus type.
   - Fares are computed with the official MSRTC **per-6km stage** model (18-Jul-2026 revision).

### MSRTC Fare Model (per 6km stage, effective 18-Jul-2026)
Fares rounded to nearest ₹5. Stage = 6 km.
| Bus type | ₹/stage |
|---|---|
| Ordinary (non-AC) | 11.40 |
| Semi Luxury (non-AC seater) | 13.65 |
| Ordinary Sleeper-Seater (non-AC) | 15.50 |
| Ordinary Sleeper (non-AC) | 16.75 |
| Shivshahi AC Seater | 14.20 |
| Shivshahi AC Sleeper | 15.35 |
| Shivneri AC Seater | 21.25 |
| Shivneri AC Sleeper | 25.35 |

Fare calculation: `stages = ceil(km / 6)`, `fare = round_to_5(stages * stageRate)`, min ₹10. The fare between any two stops on a route is computed using only the distance between those two stops (`cum_km[to] - cum_km[from]`), so a short hop costs proportionally less than the full route.

### Journey Planner & Distributed Memoization (Cache)
Calculating complex routes with transfers (A* or Dijkstra's) is heavy. We use a **Distributed Memoization** pattern:
- **Client-Side Calculation**: The first time a specific Origin-Destination pair is searched, the Flutter app downloads the graph, calculates the fastest route, and displays it.
- **`route_cache` Collection**: The calculated result is immediately saved back to Firestore in `route_cache`.
- **Cache Hits**: Any subsequent user searching the exact same Origin-Destination pair will bypass the calculation and instantly read the pre-computed route from `route_cache`, scaling infinitely with minimal compute costs.

## 4. Map Integrations
- Uses `google_maps_flutter`.
- Nearest bus stops are loaded natively into the map.
- Uses custom drawn `BitmapDescriptor` canvases (Premium Slate circles with bus icons) to highlight bus stands dynamically without needing external image assets.

## 5. Live Bus Tracking — Phase 1 Prototype vs Production
> **Decision (v2.0):** We do **not** build or install custom tracking hardware (our own NEO-6M GPS module + Bluetooth relay). This has been **dropped**.

### Production (Planned)
- State transport buses already carry **AIS-140 compliant Vehicle Location Tracking Devices (VLTDs)**.
- MSRTC plans to provide access to this existing feed.
- BussPass will consume this feed through a **VLTS Integration Adapter** (Cloud Functions / Cloud Run) which will write to Firebase RTDB `buses/{busId}`.

### Current Prototype (MVP Phase)
- Until the live VLTS data is available, BussPass simulates live tracking using **Scheduled Data Interpolation**.
- The `BusSimulator` reads the official **Timetables** and **Trip Master (Excel/trip_routes)** to calculate where a bus *should* be at the current time.
- It interpolates the bus's position along the route polyline based on average speed and elapsed time since departure.
- This deterministic simulation is pushed to Firebase RTDB `buses/{busId}` so the Flutter App and AI IVR agent can test "live" tracking logic without code changes when transitioning to the real VLTS feed.
- **Provider abstraction:** The app consumes one `LiveBus` model. Switching from the `BusSimulator` to the actual `VLTS provider` will be seamless.

## 6. AI Human Voice IVR — Google ADK
- Built with the **Google Agent Development Kit (ADK)**: `Agent` (persona + tools), `Runner.run_live(...)` with a `LiveRequestQueue`, `InMemorySessionService` (prototype).
- Model: **Gemini Live** (native streaming audio in/out). No separate STT/TTS pipeline and no DTMF menus.
- Tools (`msrtc_human_ai_agent.py`): `get_top3_upcoming_buses`, `get_route_details`, `get_fare_details`, `get_live_bus_eta`, `get_caller_ticket`, `get_caller_profile`, `update_caller_profile`, `handle_emergency`.
- Firestore collections used: `routes`, `timetables` / trip master, `tickets`, `caller_profiles`, `ivr_gateway/current_call` (IoT/hardware call trigger).
- Front-ends: `ivr_simulator_gui.py` (desktop dial pad, live mic, recordings) and `adk_live_voice.py` (headless). Production uses a SIP/media-stream bridge (Exotel / Twilio / Asterisk) into the ADK live session.
- Secrets: `GEMINI_API_KEY` must come from the environment / Secret Manager. Never hardcode it.
- Full details: `AI_HUMAN_IVR_ARCHITECTURE.md`.

