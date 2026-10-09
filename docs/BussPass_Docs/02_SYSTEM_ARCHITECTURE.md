# BussPass — System Architecture

## 1. High-Level Architecture

```mermaid
flowchart TB
    subgraph Users["Users / Channels"]
        U1["📱 Android / iOS App"]
        U2["📞 Keypad / Any Phone (Voice)"]
        U3["✉️ SMS / USSD (planned)"]
        U4["👨‍✈️ Conductor POS (planned)"]
    end

    subgraph Edge["Access Layer"]
        E1["Flutter App (offline engine on device)"]
        E2["Telephony Gateway: SIP / WebSocket / Desktop Simulator"]
        E3["USSD/SMS Handler"]
    end

    subgraph AI["AI Layer"]
        A1["Google ADK Runner + Gemini Live (streaming audio)"]
        A2["AI Human Officer Persona + Tools"]
        A3["Neural TTS (mr / hi / en)"]
    end

    subgraph Core["Shared Transit Engine"]
        C1["JourneyPlanner (time-dependent Dijkstra)"]
        C2["FareEngine (MSRTC stage model)"]
        C3["EtaEngine (traffic + dwell + halts)"]
        C4["OccupancyEngine"]
        C5["network.json (91 stops · 273 routes · 5,494 departures)"]
    end

    subgraph Cloud["Firebase Cloud"]
        F1["Auth (Google Sign-In)"]
        F2["Firestore: routes, timetables, route_fares, caller_profiles, tickets, ivr_gateway"]
        F3["Realtime DB: live bus positions"]
        F4["Storage: bus images"]
    end

    subgraph Ext["External"]
        X1["Google Maps SDK"]
        X2["OSRM routing"]
        X3["Emergency: 112 / 108 / 1091 / MSRTC control room"]
    end

    U1 --> E1
    U2 --> E2
    U3 --> E3
    U4 --> F3
    E1 --> Core
    E3 --> Core
    E2 --> A1 --> A2
    A2 -->|function calls| F2
    A2 --> A3 --> E2
    E1 --> F1 & F2 & F3 & F4
    E1 --> X1 & X2
    A2 -. guidance .-> X3
```

---

## 2. Mobile App — Layered (Clean) Architecture

```mermaid
flowchart LR
    P["Presentation\nScreens, Tabs, Widgets, Animations"] --> S["State (Riverpod)\nProviders, Notifiers"]
    S --> D["Domain / Math\nJourneyPlanner · FareEngine · EtaEngine\nOccupancyEngine · Geo · Schedule"]
    S --> SV["Services\nBusSimulator · TransitDetection · Notifications\nDirections · StateDetection · TravelPatternAlerts"]
    S --> DA["Data\nNetworkRepository · AuthRepository · LocalStore"]
    DA --> I["Infra\nFirebase · Google Maps · OSRM · SharedPreferences"]
```

| Layer | Key Modules | Responsibility |
|---|---|---|
| Presentation | `features/onboarding`, `dashboard/tabs/*`, `journey/*`, `timetable`, `state` | UI, navigation (`AuthWrapper` → `DashboardScreen` with `IndexedStack` of 4 tabs) |
| State | `data/providers/app_providers.dart`, `state_provider.dart` | Reactive DI, STC switching |
| Domain | `core/math/*` | Pure, testable algorithms with no I/O |
| Services | `core/services/*` | Device and OS integrations, simulation |
| Data | `data/repositories/*`, `data/models/*` | Bundle + Firestore merge, local persistence |

### 2.1 Core Engines

| Engine | File | Model |
|---|---|---|
| Journey Planner | `journey_planner.dart` (~1,100 LOC) | Time-dependent Dijkstra over stops; labels `(stop, transfers, tier)`; max 3 transfers; 10-min min transfer; 25-min penalty; walk ≤ 1.5 km @ 4.5 km/h; rank and diversify to 4 |
| Fare Engine | `fare_engine.dart` | `stages = ⌈km/6⌉`; `fare = max(₹10, round5(stages × rate))`; concession % applied |
| ETA Engine | `eta_engine.dart` | `t = distance / v_eff + stops × 70 s + halts`; `v_eff` depends on trip length, time of day, stop density; traffic factor +8% / 0 / −18% / −35% |
| Occupancy | `occupancy_engine.dart` | POS-reported (ground truth) else modelled (peak window, weekday, distance from origin, class) |
| Bus Simulator | `bus_simulator.dart` | Deterministic position = f(service, departure, clock); hash-based delay per bus; 220 buses; 3 s tick |
| Transit Detection | `transit_detection_service.dart` | Speed ≥ 15 km/h for 2 min → within 50 m of corridor → match live bus → < 100 m for 3 min ⇒ ON BOARD |
| State Detection | `state_detection_service.dart` | Offline GPS bounding-box → STC + brand palette |

---

## 3. AI Human Voice IVR Architecture

```mermaid
sequenceDiagram
    autonumber
    participant C as Caller (any phone)
    participant G as Telephony Gateway / Simulator
    participant R as ADK Runner + LiveRequestQueue
    participant M as Gemini Live (Officer persona)
    participant T as Tools (msrtc_human_ai_agent.py)
    participant F as Firestore

    C->>G: Call connects (Caller ID)
    G->>T: get_caller_profile / get_caller_ticket
    T->>F: read caller_profiles, tickets
    F-->>T: name, language, history, active ticket
    G->>R: Start live session (context injected)
    M-->>C: Greeting in Hindi (offers Marathi/English)
    C->>R: Streams 16 kHz PCM audio
    R->>M: Audio blobs
    M->>T: get_top3_upcoming_buses(origin, dest)
    T->>F: routes / timetables / trip master
    F-->>T: departures
    T-->>M: Top-3 with platform, type, fare
    M-->>C: Natural spoken answer (streaming audio)
    M->>T: update_caller_profile(name, mood, summary)
    T->>F: write caller_profiles
    G->>G: Save call recordings (caller_input / ai_output .wav)
```

### 3.1 AI Tools

| Tool | Purpose | Data Source |
|---|---|---|
| `get_caller_profile` / `update_caller_profile` | CRM memory: name, language, mood, frequent routes | Firestore `caller_profiles` |
| `get_top3_upcoming_buses` | 3 closest departures from the current time, with fuzzy city matching | `routes`, `timetables`, Trip Master |
| `get_route_details` | Via-stops, duration, bus types | `routes` |
| `get_fare_details` | Fare by bus type (MSRTC stage formula) | Computed |
| `get_live_bus_eta` | Live location and ETA for a bus number | Live feed |
| `get_caller_ticket` | Active ticket by phone number | `tickets` |
| `handle_emergency` | Accident / Unsafe / Medical / Breakdown / Fire / Missing → priority, empathy line, contacts, guidance | Rule table |

### 3.2 Deployment Options
1. **Cloud server** (Docker / Cloud Run) exposing WebSockets for WebRTC and mobile audio.
2. **SIP/VoIP gateway** (Exotel / Twilio / Asterisk) whose webhook streams PSTN calls to the AI server.
3. **Desktop simulator** (`ivr_simulator_gui.py`, Tkinter) with dial pad, DTMF, live mic, and recordings.
4. **IoT trigger**: a hardware device sets `ivr_gateway/current_call.status = "ringing"`; the simulator auto-answers.

---

## 4. Data Pipeline

```mermaid
flowchart LR
    A["msrtc_data.js\nstands, routes, waypoints"] --> B
    A2["master_timetables.json\nscraped + verified"] --> B
    A3["Trip_Master XLSX\n(official MSRTC Ahilyanagar)"] --> P["process_trip_master.py"] --> B
    B["build_dataset.js\nresolve coords · cum_km · schedules · validate"] --> N["assets/data/network.json"]
    N --> APP["Flutter app (offline)"]
    N --> S["seed_firestore.js / upload_trip_master.py"] --> FS["Firestore"]
    IMG["Bus-images/"] --> UP["upload_images.js"] --> ST["Firebase Storage"]
    FS --> IVR["Voice AI tools"]
```

---

## 5. Data Model (Firestore)

| Collection | Key Fields |
|---|---|
| `bus_stops` | id, name, city, lat, lng |
| `routes` | id, bus type, total distance, `stops[] {stop_id, name, city, lat, lng, seq, cum_km}` |
| `route_fares` | `by_type`, `segments{"from__to": {distance_km, by_type}}` |
| `timetables` / trip master | route, departure times, platform, bus type |
| `route_cache` | pre-computed O-D results (distributed memoization) |
| `tickets` | id, phone, route, legs, status (upcoming / active / completed / cancelled / expired), QR payload |
| `caller_profiles` | phone, name, preferred language, mood, call history, frequent routes |
| `ivr_gateway/current_call` | status (ringing / answered), phone |
| RTDB `live_buses/{busId}` | lat, lng, speed, heading, next stop, timestamp |

---

## 6. Security & Privacy Architecture
- Firebase Auth for identity; Firestore security rules scoped per collection.
- Secrets (`serviceAccountKey.json`, `google-services.json`, `.env`) are git-ignored. API keys must be loaded from environment variables or a secret manager, never hardcoded.
- Rider GPS for transit detection stays **in memory on device**.
- Caller data limited to what's needed for service (CRM fields); planned 24-hour purge for location data and DPDP Act 2023 alignment.
- Emergency responses are rule-based (deterministic), not left to free-form generation.

---

## 7. Scalability Roadmap

| Metric | Prototype | Production |
|---|---|---|
| Buses tracked | 220 simulated | 50,000+ real (AIS-140 VLTS) |
| Concurrent users | ~100 | 10M+ |
| RTDB | single instance | sharded by state/region |
| Planner | on-device in-memory | on-device + `route_cache` / Redis |
| IVR | desktop / sandbox | multi-region SIP + autoscaled AI workers |
| GPS interval | fixed | adaptive (5 s city / 30 s highway) |
