# BussPass — Workflows

## 1. App Onboarding & Launch

```mermaid
flowchart TD
    A([Launch]) --> B{Logged in?}
    B -->|No| C[Language Select: en / mr / hi / kn]
    C --> D[Google Sign-In]
    D --> E
    B -->|Yes| S[Smart Splash: GPS → State/STC detection]
    S --> E[Dashboard]
    E --> H[Home] & M[Map] & P[Passes] & PR[Profile]
```

## 2. Journey Planning → Travel

```mermaid
flowchart TD
    A[Home: 'Where to?'] --> B[Search: origin, destination, time]
    B --> C[Load offline network.json → TransitGraph]
    C --> D[Time-dependent Dijkstra\n≤3 transfers · 10 min min-transfer · 25 min penalty]
    D --> E[Rank: fastest / cheapest / fewest changes]
    E --> F[Diversify → up to 4 itineraries, direct guaranteed]
    F --> G[Journey Details\nlegs, fare, ETA, occupancy, bus photo, polyline]
    G --> H{User > 100 m from stand?}
    H -->|Yes| W[Walk-to-Stand nav (OSRM walking)]
    H -->|No| L
    W --> L[Live Navigation\nGPS · ETA recalc · arrival & halt alerts]
    L --> T[Transit Detection confirms on-board bus]
    T --> Z([Arrive → ticket marked completed])
```

## 3. Transit Detection Decision Tree

```mermaid
flowchart TD
    A[GPS trail, several minutes] --> B{Speed ≥ 15 km/h for 2+ min?}
    B -->|No| S1[STATIONARY]
    B -->|Yes| C{Within 50 m of bus corridor?}
    C -->|No| S2[PRIVATE VEHICLE]
    C -->|Yes| D{Live bus position matches?}
    D -->|No| S3[POSSIBLY ON BUS → ask rider]
    D -->|Yes| E{Agreement < 100 m for 3+ min?}
    E -->|Yes| S4[ON BOARD — bus identified]
    E -->|No| S3
```

## 4. AI Human Voice IVR Call Flow

```mermaid
flowchart TD
    A([Caller dials helpline from any phone]) --> B[Gateway receives call + Caller ID]
    B --> C[Pre-fetch caller profile & active ticket from Firestore]
    C --> D[AI Officer greets in Hindi;\nrepeat callers greeted by name in preferred language]
    D --> E[Caller speaks freely: mr / hi / en / mixed]
    E --> F{Intent}
    F -->|Bus timings| G[get_top3_upcoming_buses]
    F -->|Route / via stops| H[get_route_details]
    F -->|Fare| I[get_fare_details]
    F -->|Where is my bus| J[get_live_bus_eta / get_caller_ticket]
    F -->|Emergency| K[handle_emergency → 112 / 108 / 1091 / MSRTC control room]
    F -->|Language switch| D
    G & H & I & J --> L[Intent acknowledged → spoken answer:\ntime, platform/bay, bus type, fare, deboarding stand]
    K --> L
    L --> M{More questions?}
    M -->|Yes| E
    M -->|No| N[update_caller_profile: name, mood, summary]
    N --> O[Save recordings → hang up]
```

**Example exchange (Marathi):**
> **Caller:** "संगमनेरहून नाशिकला बस कधी आहे?"
> **AI:** "नमस्कार! मला समजले, तुम्हाला संगमनेर ते नाशिक प्रवासाबद्दल माहिती हवी आहे. पुढच्या तीन बस आहेत — १२:४० शिवशाही, प्लॅटफॉर्म ३…"

## 5. Night-Halt Safety Alert (planned conductor flow + built rider alerts)

```mermaid
sequenceDiagram
    participant Co as Conductor POS
    participant CF as Cloud Function
    participant App as Rider App
    participant Ph as Feature Phone
    Co->>CF: Tap "HALT STOP"
    CF->>App: Push: halt started (20 min)
    Note over CF: T+15 min
    CF->>App: "Bus leaves in 5 min" (busspass_halt channel)
    Note over CF: T+18 min
    CF->>Ph: Automated voice call in native language
    CF->>Co: Headcount: confirmed vs not-confirmed (names, seats)
```

## 6. Travel-Pattern Alerts

```mermaid
flowchart LR
    A[Search O→D] --> B[LocalStore increments count]
    B --> C{count ≥ 2 and feature on?}
    C -->|Yes| D[Schedule ONE notification 20 min before next departure\ndeterministic ID → replaces, never stacks]
    C -->|No| E[No action]
    F[User disables in Profile] --> G[Cancel all pattern alerts]
```

## 7. Ticket Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Upcoming
    Upcoming --> Active: boarded / QR validated
    Upcoming --> Cancelled
    Upcoming --> Expired
    Active --> Completed
    Completed --> [*]
```

## 8. Data Pipeline Workflow
1. Update the sources (`msrtc_data.js`, `master_timetables.json`, official Trip Master XLSX).
2. `python scripts/process_trip_master.py` merges official trips into `network.json`.
3. `node scripts/build_dataset.js` resolves coordinates, computes `cum_km`, synthesizes schedules, and validates geometry.
4. `node scripts/seed_firestore.js` (+ `upload_trip_master.py`) loads routes, fares, and timetables into Firestore.
5. `node scripts/verify_seed.js` checks counts. `upload_images.js` pushes bus photos.
6. The app ships the new bundle; Firestore overlays live updates without an app release.

## 9. Development Workflow
- Flutter: `flutter pub get` → `flutter run` (Android/iOS).
- IVR: activate `ivr_venv` → set `GEMINI_API_KEY` in env → `python ivr_simulator_gui.py` (or `adk_live_voice.py` for headless mic mode).
- Git: feature commits (`feat:`, `fix:`, `design:`, `docs:`); secrets stay out of the repo.
