# BussPass - Your Travel Partner

**BussPass** is a smart, multilingual Android application designed for MSRTC (Maharashtra State Road Transport Corporation) bus commuters. It provides real-time journey planning, accurate fare computation, offline-capable route search, live bus tracking, and digital pass management.

This project was developed for the **Smart India Hackathon (SIH)** under the theme of modernizing public transport for citizens of Maharashtra.

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Solution Overview](#solution-overview)
- [Application Flow](#application-flow)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Technology Stack](#technology-stack)
- [Data Pipeline](#data-pipeline)
- [Fare Engine](#fare-engine)
- [Journey Planner Algorithm](#journey-planner-algorithm)
- [Localization](#localization)
- [Setup and Installation](#setup-and-installation)
- [Environment Variables](#environment-variables)
- [Scripts Reference](#scripts-reference)

---

## Problem Statement

Millions of MSRTC commuters face the following challenges daily:

- No centralized digital platform to search and plan multi-stop bus journeys.
- Fare calculation is opaque and inconsistent across bus types (Ordinary, Shivshahi, Shivneri, Hirkani, etc.).
- No offline access to timetables in rural connectivity zones.
- Bus schedules exist only on physical notice boards at bus stands.
- No multilingual support for regional language speakers (Marathi, Hindi, Kannada).
- Ticket management is paper-based with no digital alternative.

---

## Solution Overview

BussPass digitizes the entire MSRTC commuter experience. It provides a mobile-first application that:

1. Allows commuters to search for routes between any two stops in the MSRTC network.
2. Computes the optimal journey path using a time-dependent Dijkstra algorithm accounting for transfers, bus type tiers, fare, and total travel time.
3. Displays accurate, MSRTC-official stage-based fares for every leg of the journey and for every bus type.
4. Works offline via a bundled network.json dataset that is pre-built from verified MSRTC timetable data.
5. Provides a live map to view nearby bus stands and active buses.
6. Supports Marathi, Hindi, Kannada, and English with a single tap.
7. Manages digital pass purchases and QR-based ticket scanning.

---

## Application Flow

```
[ Launch App ]
      |
      v
[ Authentication Check ]
      |
      +--- No User -----> [ Language Selection Screen ]
      |                            |
      |                            v
      |                   [ Auth Screen (Google Sign-In) ]
      |                            |
      v                            v
[ Dashboard (Authenticated) ] <----+
      |
      +--- Home Tab
      |        |
      |        +---> [ Search Bar ]
      |        |             |
      |        |             v
      |        |     [ Journey Search Screen ]
      |        |             |
      |        |     [ User enters Origin + Destination ]
      |        |             |
      |        |             v
      |        |     [ JourneyPlanner.plan() ]
      |        |       |
      |        |       +-- Loads TransitNetwork (bundled network.json)
      |        |       +-- Builds adjacency graph (TransitGraph)
      |        |       +-- Runs time-dependent Dijkstra
      |        |       +-- Ranks by preference (fastest / cheapest / fewest changes)
      |        |       +-- Diversifies results (guarantees direct option if exists)
      |        |             |
      |        |             v
      |        |     [ Itinerary Results List ]
      |        |             |
      |        |             v
      |        |     [ Journey Details Screen ]
      |        |       |
      |        |       +-- Per-leg breakdown: bus type, fare, duration
      |        |       +-- Bus image (from Firebase Storage)
      |        |       +-- Polyline map of the route
      |        |       +-- Boarding reminder notification scheduled
      |        |             |
      |        |             v
      |        |     [ Live Navigation Screen ]
      |        |       |
      |        |       +-- Real-time GPS tracking
      |        |       +-- ETA recalculation with traffic model
      |        |       +-- Halt and arrival alerts (local notifications)
      |        |
      |        +---> [ Quick Actions ]
      |                  |
      |                  +-- Live Map   --> [ Map Tab ]
      |                  +-- Timetables --> [ Timetables Screen ]
      |                  +-- Buy Pass   --> [ Passes Tab ]
      |                  +-- My Passes  --> [ Passes Tab ]
      |
      +--- Map Tab
      |        |
      |        +-- Google Maps with custom sage-dark theme
      |        +-- Nearby bus stands as custom rendered markers
      |        +-- Marker tap shows stand name and service count
      |
      +--- Passes Tab
      |        |
      |        +-- Digital ticket list (QR-based)
      |        +-- QR scanner for validation
      |
      +--- Profile Tab
               |
               +-- Account info
               +-- Notification permission toggle
               +-- Language preference
               +-- Concession category (Senior / Student / Women / Disability)
```

---

## Features

### Journey Planning

- Multi-leg journey planning across the entire MSRTC network.
- Transfers supported at major interchange stops (Nashik CBS, Pune Station, Mumbai Central, etc.).
- Preference-based sorting: fastest arrival, cheapest fare, or fewest changes.
- Guaranteed diversity in results — always shows a direct option when one exists.

### Fare Engine

- Implements the official MSRTC stage-based fare model (effective 18 July 2026 revision).
- Supports all MSRTC bus classes: Ordinary, Semi Luxury (Hirkani / Ashiad), Shivshahi, Shivneri, Ordinary Sleeper, Shivneri Sleeper, E-Shiva-E, and E-Shivneri.
- Concession support: Child (50%), Women (50%), Senior Citizen (free), Student (50%), Person with Disability (free).
- Per-stop-pair fare computation — a short-hop fare is always proportional to distance.

### Offline-First Network

- The full MSRTC route graph (91 stops, 273 routes, 602 services, 5,494 departures) is bundled as a compact offline dataset.
- The app works without internet for route search and fare queries.
- Firebase Firestore is used for real-time overlays (live bus positions, timetable updates).

### Live Map

- Full-screen Google Maps view with a custom dark-sage theme.
- All nearby bus stands plotted as custom-rendered markers.
- Accurate route polylines that follow real road corridors, not straight-line approximations.

### Notifications

- Boarding reminders scheduled before departure.
- Arrival alerts as the bus approaches the destination stop.
- Halt stop alerts for overnight journeys.

### Multilingual Support

- English, Marathi, Hindi, and Kannada supported natively.
- Language can be changed at any time from the Home Screen (A/अ button).
- Selected language is persisted across app restarts.

### Digital Passes

- QR-code-based digital tickets.
- Pass scanning and validation.
- Multiple pass types: daily, weekly, monthly, and student passes.

---

## Architecture

The application follows a layered, feature-first architecture:

```
Presentation Layer   (Flutter Widgets, Screens, Tabs)
        |
        v
State Management     (Riverpod Providers)
        |
        v
Domain / Math Layer  (JourneyPlanner, FareEngine, EtaEngine, OccupancyEngine)
        |
        v
Data Layer           (Repositories, Models, Firebase SDK)
        |
        v
Infrastructure       (Firebase Auth, Firestore, Firebase Storage, Google Maps)
```

Key design decisions:

- Riverpod is used exclusively for state management. No setState in business logic.
- Offline-first: The network.json bundle is the single source of truth for the route graph. Firestore overlays supplement it but are not required for core search.
- Math is pure Dart: All planning, fare, and ETA logic is implemented as pure Dart classes with no external dependencies, making them fully unit-testable.
- Immutable models: All domain models (NetworkStop, TransitRoute, TransitService, Itinerary, JourneyLeg) are immutable value objects.

---

## Project Structure

```
SIH-BussPass/
|
|-- busspass/                         Flutter application
|   |-- lib/
|   |   |-- core/
|   |   |   |-- math/
|   |   |   |   |-- journey_planner.dart     Time-dependent Dijkstra planner
|   |   |   |   |-- fare_engine.dart         MSRTC stage fare model
|   |   |   |   |-- eta_engine.dart          ETA with traffic model
|   |   |   |   |-- occupancy_engine.dart    Seat occupancy estimation
|   |   |   |   |-- geo.dart                 Haversine distance utilities
|   |   |   |   |-- schedule.dart            Departure and arrival scheduling
|   |   |   |-- services/
|   |   |   |   |-- notification_service.dart
|   |   |   |   |-- transit_detection_service.dart
|   |   |   |   |-- travel_pattern_alerts.dart
|   |   |   |-- utils/
|   |   |       |-- bus_image_helper.dart    Firebase Storage image URL map
|   |   |
|   |   |-- data/
|   |   |   |-- models/
|   |   |   |   |-- network_models.dart      NetworkStop, TransitRoute, etc.
|   |   |   |   |-- ticket.dart              Digital pass and ticket models
|   |   |   |   |-- live_bus.dart            Real-time bus state
|   |   |   |-- providers/
|   |   |   |   |-- app_providers.dart       All Riverpod providers
|   |   |   |   |-- auth_provider.dart
|   |   |   |-- repositories/
|   |   |       |-- network_repository.dart  Merges bundle and Firestore overlay
|   |   |       |-- auth_repository.dart
|   |   |       |-- local_store.dart         SharedPreferences wrapper
|   |   |
|   |   |-- features/
|   |   |   |-- onboarding/                  Language selection and Auth screens
|   |   |   |-- dashboard/                   4-tab main screen
|   |   |   |-- journey/                     Search, details, live navigation
|   |   |   |-- timetable/                   Static timetable viewer
|   |   |
|   |   |-- theme/                           Design system (colors, typography, widgets)
|   |   |-- main.dart
|   |
|   |-- assets/
|   |   |-- data/network.json                Bundled offline route graph (439 KB)
|   |   |-- translations/                    en / mr / hi / kn JSON files
|   |
|   |-- pubspec.yaml
|
|-- scripts/                          Data pipeline (Node.js)
|   |-- msrtc_data.js                 Master route, stop, and fare definitions
|   |-- build_dataset.js              Compiles network.json from all sources
|   |-- seed_firestore.js             Seeds Firestore with routes and fare matrices
|   |-- master_timetables.json        Scraped and verified MSRTC timetable rows
|
|-- Bus-images/                       Source bus type photographs
|-- ARCHITECTURE.md                   Extended architectural notes
|-- README.md
```

---

## Technology Stack

### Mobile Application

| Technology | Purpose |
|---|---|
| Flutter (Dart) | Cross-platform mobile framework |
| Riverpod 3 | State management and dependency injection |
| Firebase Authentication | Google and Facebook sign-in |
| Cloud Firestore | Real-time database for routes and timetables |
| Firebase Storage | Bus type images |
| Google Maps Flutter | Live map, route polylines, custom markers |
| Easy Localization | Multilingual support (en, mr, hi, kn) |
| Flutter Animate | Micro-animations and transitions |
| Flutter Local Notifications | Boarding and arrival alerts |
| Mobile Scanner | QR code scanning for ticket validation |
| QR Flutter | QR code generation |
| Geolocator | Device GPS for nearest-stop lookup |

### Data Pipeline

| Technology | Purpose |
|---|---|
| Node.js | Dataset compilation scripts |
| Firebase Admin SDK | Firestore and Storage seeding |
| Haversine geometry | Distance computation for stop-pair fares |

---

## Data Pipeline

The offline route graph is built by a Node.js pipeline:

```
scripts/msrtc_data.js
   |
   Contains:
     STANDS       - 91 bus stands with exact GPS coordinates
     WAYPOINTS    - Road junction reference points
     ROUTES       - Curated corridor definitions with via-stops and bus types
     computeFare  - Official MSRTC stage fare model
   |
   v
scripts/build_dataset.js
   |
   Reads: msrtc_data.js + master_timetables.json (988 timetable rows)
   Performs:
     - Resolves via-stop city names to exact GPS coordinates
     - Computes cumulative distance at each stop along the corridor
     - Synthesizes headway-based departure schedules for corridors without timetables
     - Validates geometry (rejects pairs where declared km is implausible)
     - Raises corridor distance to geometric floor when declared distance is too short
   |
   v
busspass/assets/data/network.json
   |
   Contains: 91 stops, 273 routes, 602 services, 5,494 departures (439 KB)
   Loaded at: app startup, cached in memory by NetworkRepository
```

To rebuild the dataset after modifying routes or timetables:

```bash
cd scripts
node build_dataset.js
```

To seed Firestore with the full route graph and per-stop fare matrices:

```bash
cd scripts
node seed_firestore.js
```

---

## Fare Engine

The FareEngine class in `lib/core/math/fare_engine.dart` implements the official MSRTC fare schedule effective 18 July 2026.

**Formula:**

```
stages   = ceil(distance_km / 6)
raw_fare = stages x stage_rate
base_fare = max(10, round_to_nearest_5(raw_fare))
final_fare = base_fare x (1 - concession_percent / 100)
```

**Stage rates (rupees per 6 km stage):**

| Bus Class | Rate (Rs. per stage) |
|---|---|
| Ordinary | 11.40 |
| Semi Luxury (Hirkani / Ashiad) | 13.65 |
| Ordinary Sleeper-Seater | 15.50 |
| Ordinary Sleeper | 16.75 |
| Shivshahi AC Seater | 14.20 |
| Shivshahi AC Sleeper | 15.35 |
| Shivneri AC Seater | 21.25 |
| Shivneri AC Sleeper | 25.35 |

**Concession categories:**

| Category | Discount |
|---|---|
| Adult | 0% |
| Child (5 to 12 years) | 50% |
| Senior Citizen (65 and above) | 100% (free) |
| Women - Mahila Samman Yojana | 50% |
| Student | 50% |
| Person with Disability | 100% (free) |

---

## Journey Planner Algorithm

The JourneyPlanner class (`lib/core/math/journey_planner.dart`) implements a time-dependent Dijkstra over the transit graph.

**State space:**

Each node in the priority queue is a label `(stop_id, transfers, service_tier, cost_minutes)`. The service tier is included in the key so that a slower, cheaper bus class (Ordinary) is not pruned merely because a faster, more expensive class (Shivneri) already settled the same stop.

**Cost function:**

```
cost = elapsed_minutes + (transfer_count x transfer_penalty_minutes)
```

The default transfer penalty is 40 minutes. This means the planner prefers a direct route that takes slightly longer over a route requiring one extra change.

**Post-processing:**

1. _rank() sorts results by user preference (fastest / cheapest / fewest changes / earliest arrival).
2. _diversify() removes near-duplicate itineraries (same route and class, arriving within 45 minutes). Always guarantees one direct option and one cheapest option are visible.

**Default configuration (PlannerConfig):**

| Parameter | Default |
|---|---|
| Max transfers | 2 |
| Max wait per transfer | 120 minutes |
| Min transfer time | 10 minutes |
| Transfer penalty | 40 minutes |
| Max walk distance | 1.5 km |
| Result count | 5 |

---

## Localization

The app uses easy_localization for multilingual support. Translation files are in `assets/translations/`.

| Code | Language |
|---|---|
| en | English |
| mr | Marathi |
| hi | Hindi |
| kn | Kannada |

The user can switch language at any time using the **A/अ** button on the Home Screen. The selected locale is persisted across app restarts.

To add a new translation key:
1. Add the key-value pair to each file in `busspass/assets/translations/`.
2. Use `'key'.tr()` in the Dart widget.

---

## Setup and Installation

### Prerequisites

- Flutter SDK 3.24 or higher
- Dart SDK 3.11 or higher
- Android Studio or VS Code with Flutter extension
- A Firebase project with Authentication, Firestore, and Storage enabled
- Google Maps API key (Android)
- Node.js 18 or higher (for data pipeline scripts only)

### Steps

1. Clone the repository:

```bash
git clone https://github.com/PrashilD15/BussPass-SIH.git
cd BussPass-SIH
```

2. Install Flutter dependencies:

```bash
cd busspass
flutter pub get
```

3. Configure Firebase:
   - Create a Firebase project at https://console.firebase.google.com
   - Enable Google Sign-In under Authentication
   - Create a Firestore database in Native mode
   - Enable Firebase Storage
   - Download google-services.json and place it at `busspass/android/app/google-services.json`
   - Run `flutterfire configure` to regenerate firebase_options.dart

4. Set your Google Maps API key in `busspass/android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE" />
```

5. (Optional) Run the data pipeline:

```bash
cd scripts
npm install
# Place your Firebase service account key at scripts/serviceAccountKey.json
node build_dataset.js
node seed_firestore.js
```

6. Run the app:

```bash
cd busspass
flutter run
```

---

## Environment Variables

The following files must not be committed to version control and are listed in .gitignore:

| File | Purpose |
|---|---|
| `busspass/android/app/google-services.json` | Firebase Android configuration |
| `busspass/lib/firebase_options.dart` | FlutterFire generated configuration |
| `scripts/serviceAccountKey.json` | Firebase Admin SDK service account |
| `busspass/lib/core/constants/api_keys.dart` | Google Maps API key |

---

## Scripts Reference

| Script | Command | Description |
|---|---|---|
| Build offline dataset | `node scripts/build_dataset.js` | Compiles network.json from curated data and timetables |
| Seed Firestore | `node scripts/seed_firestore.js` | Writes routes and fare matrices to Firestore |
| Verify seed | `node scripts/verify_seed.js` | Checks Firestore document counts after seeding |
| Report routes | `node scripts/report_routes.js` | Prints a summary of all loaded corridors |
| Upload bus images | `node scripts/upload_images.js` | Uploads Bus-images/ folder to Firebase Storage |

---

Developed for Smart India Hackathon (SIH) 2024-25.
