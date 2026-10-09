# BussPass — Overall Project Report

**Smart India Hackathon 2026-27**
**Project:** BussPass — Your Travel Partner
**Date:** 09 October 2026

---

## Table of Contents
1. Abstract
2. Introduction & Background
3. Problem Definition
4. Objectives
5. Literature / Existing Systems Review
6. Proposed System
7. System Architecture (overview)
8. Module-wise Implementation
9. Algorithms
10. Data & Dataset
11. Technology Stack
12. Testing & Validation
13. Results
14. Uniqueness & Innovation
15. Impact Analysis
16. Limitations
17. Future Scope
18. Conclusion
19. Appendix: Repository Map

---

## 1. Abstract
BussPass is a multi-channel public-transport platform for India's state road transport corporations (STCs), starting with MSRTC (Maharashtra). It combines an **offline-first Flutter mobile app** with an **AI-powered conversational voice officer** reachable from any phone. A shared transit engine (a time-dependent Dijkstra planner, the official MSRTC stage-fare model, and a traffic-, dwell-, and halt-aware ETA model) produces consistent answers on every channel. The prototype covers 91 bus stands, 273 routes, 602 services, and 5,494 departures, supports 4 app languages and 3 voice languages, and includes safety features such as night-halt alerts and in-call emergency triage.

## 2. Introduction & Background
State buses are the backbone of intercity and rural mobility in India, carrying ~70 million passengers a day. Railways have "Where is my Train", but bus riders rely on enquiry counters, notice boards, and asking around. Digital tools that do exist assume a smartphone, English literacy, and constant connectivity, which leaves out much of the core ridership: rural, elderly, and low-income travellers.

## 3. Problem Definition
- No stop-level, multi-transfer journey planning.
- Opaque fare structures across bus classes and concessions.
- No offline access in low-connectivity regions.
- Language barriers (Marathi, Hindi, Kannada speakers).
- Exclusion of feature-phone and non-literate users.
- Robotic DTMF IVRs that frustrate callers.
- Passengers stranded at night halts or missing their stops.
- Unreliable "live" tracking.

## 4. Objectives
1. Deliver accurate, offline, multi-transfer journey planning.
2. Show official fares, including concessions.
3. Predict realistic ETAs.
4. Provide a human-like voice assistant for any phone, in native languages.
5. Improve passenger safety with alerts and emergency guidance.
6. Design for multi-state scalability and B2G deployment.

## 5. Existing Systems Review

| System | Strengths | Gaps |
|---|---|---|
| MSRTC "Aapli ST" app | Official, some GPS tracking | No transfer planning, limited offline, no voice-first channel |
| Google Maps transit | Great UX in metros | Patchy STC intercity data, no STC fares/concessions, no feature-phone path |
| Conventional IVR helplines | Reach feature phones | Menu-driven, robotic, no context, no memory |
| Enquiry counters | Human empathy | Limited hours, queues, not scalable |

**Gap:** No solution combines human-like empathy, feature-phone reach, offline intelligence, and official fare and timetable accuracy.

## 6. Proposed System
BussPass has three access channels sharing one engine:
- **Mobile app**: planner, fares, ETAs, live map and navigation, alerts, tickets/passes, i18n, accessibility.
- **AI Human Voice Officer**: Gemini Live streaming conversation, tool-calling into Firestore data, CRM memory, emergency triage.
- **SMS/USSD** (planned): thin I/O layer over the same graph.

## 7. System Architecture (overview)
See **02_SYSTEM_ARCHITECTURE.md** for diagrams. Summary:
- **Presentation → Riverpod state → Domain engines / Services → Repositories → Firebase/Maps/OSRM** in the app.
- **Gateway → ADK Runner → Gemini Live → Tools → Firestore → TTS** for voice.
- **Pipeline:** official sources → `build_dataset.js` → `network.json` → app + Firestore.

## 8. Module-wise Implementation

| Module | Implementation Highlights |
|---|---|
| Onboarding | Language select → Google Sign-In → GPS STC detection |
| Dashboard | 4 tabs (Home, Map, Passes, Profile) kept alive via `IndexedStack` |
| Journey Search & Details | Up to 4 diversified itineraries; per-leg fare, ETA, occupancy, bus photo, OSRM polyline |
| Walk-to-Stand | OSRM walking route, live distance/ETA, "I've arrived" hand-off |
| Live Navigation | Real GPS, road-snapped route, ETA recalculation, arrival and halt alerts |
| Map Tab | Custom-styled Google Map, nearby stands, 220-bus deterministic fleet |
| Timetable | Nearest-first departures with search |
| Passes & Tickets | QR generation, scanner, offline storage, lifecycle states |
| Profile | Language, concession category, theme, larger text, reduce motion, per-channel notifications |
| Notifications | 4 OS channels; failure-tolerant; exact-alarm permission handling |
| Travel-Pattern Alerts | Learns repeated O-D searches, schedules a single non-stacking reminder |
| Voice AI Engine | `msrtc_human_ai_agent.py`: tools, persona, CRM, emergency rules |
| IVR Simulator | `ivr_simulator_gui.py`: Tkinter dial pad, DTMF, live mic streaming, recordings, IoT trigger |
| Headless Voice | `adk_live_voice.py`: mic ↔ Gemini Live loop |
| Data Pipeline | Node.js + Python scripts for building, seeding, verifying, and uploading |

## 9. Algorithms

### 9.1 Journey Planner (time-dependent Dijkstra)
- Nodes are stops; edges are consecutive service calls plus walk links (≤ 1.5 km).
- Each label holds (stop, transfers, service tier, cost, arrival time).
- A connection is valid only if departure ≥ arrival + 10 minutes.
- Cost = travel time + 25 minutes per transfer.
- Max 3 transfers; max 14-hour wait (overnight connections allowed).
- Results are ranked (fastest / cheapest / fewest changes), then diversified (near-duplicates removed, direct option guaranteed).

### 9.2 Fare
`stages = ⌈d/6⌉; fare = max(10, round5(stages × rate)); final = fare × (1 − concession%)`

### 9.3 ETA
`t = d / v_eff + n_stops × 70 s + ⌊t_run / interval⌋ × break`
`v_eff` = class cruise speed × trip-length factor × time-of-day factor × stop-density factor × traffic factor.

### 9.4 Transit Detection
A 4-gate decision tree over a sustained GPS window (speed → corridor → bus match → sustained agreement).

### 9.5 Voice Top-3 Departures
Fuzzy city match → collect departures for the O-D pair from routes, timetables, and Trip Master → convert to minutes → keep those ≥ now → sort → take 3 → attach platform, bus type, fare.

## 10. Data & Dataset
- **Sources:** curated MSRTC stand and route data, scraped and verified timetables (988 rows), and the **official MSRTC Trip Master XLSX** (Ahilyanagar division).
- **Output:** `network.json`: 91 stops, 273 routes, 602 services, 5,494 departures, ~439 KB.
- **Cloud:** Firestore collections for routes, fares (with per-segment fares), timetables, tickets, caller profiles, and the IVR gateway; Storage for bus images.

## 11. Technology Stack

| Area | Technologies |
|---|---|
| Mobile | Flutter 3.24, Dart 3.11, Riverpod, flutter_animate, easy_localization |
| Maps & Location | Google Maps SDK, OSRM, Geolocator |
| Notifications | flutter_local_notifications, timezone |
| Tickets | qr_flutter, mobile_scanner |
| Backend | Firebase Auth, Firestore, RTDB, Storage |
| AI Voice | Google ADK, Gemini Live (streaming audio), neural TTS, PyAudio |
| Pipeline | Node.js 18, Firebase Admin SDK, Python 3 + openpyxl |
| Simulator | Python Tkinter |

## 12. Testing & Validation

| Area | Method | Outcome |
|---|---|---|
| Planner correctness | Known O-D pairs incl. 3-transfer village routes (e.g., Bhandardara → Chandrapur) | Valid, time-consistent itineraries |
| Fare | Compared with the MSRTC published stage table | Matches formula and ₹5 rounding |
| ETA | Mumbai–Pune Shivneri (~3h15m), Pune–Nashik Semi-Luxury (~5h) | Within a few minutes of published times |
| Simulator | Deterministic position assertions | Reproducible across runs |
| Notifications | Permission denied / granted on Android 13+ and iOS | App remains functional |
| Voice AI | Recorded test calls (caller_input / ai_output WAV logs) in Hindi and Marathi | Correct intent, top-3 answers, natural replies |
| Dark mode / a11y | Manual audit, 1.4× text | WCAG AA contrast |

## 13. Results
- A working cross-platform app with **no placeholder data**.
- Sub-second offline journey planning on device.
- A voice officer that holds real-time, multilingual conversations, answers timetable, fare, and route queries from live Firestore data, remembers callers, and handles emergencies.
- A repeatable data pipeline built on official STC data.

## 14. Uniqueness & Innovation
See **06_UNIQUENESS.md**. Highlights: the AI Human Officer, feature-phone inclusion, caller-ID context, top-3 departures, code-switch understanding, emergency triage, one engine for every channel, stop-level time-dependent Dijkstra, the calibrated ETA model, the deterministic simulator, transit detection, and night-halt alerts.

## 15. Impact Analysis

| Dimension | Expected Impact |
|---|---|
| Social | Digital inclusion of elderly, rural, and non-literate riders |
| Safety | Fewer halt strandings and missed stops; faster emergency guidance |
| Economic | Lower enquiry-counter load; fewer wasted trips and wait times |
| Environmental | A better bus experience encourages shared transport over private vehicles |
| Governance | Call and usage analytics help STCs plan routes and service quality |

## 16. Limitations
- Live bus positions are simulated until a AIS-140 VLTS feed is integrated.
- PSTN telephony isn't connected yet (the desktop simulator and headless mode work).
- The dataset currently focuses on Maharashtra/MSRTC; other STCs are registered but need data.
- SMS/USSD and the conductor dashboard are designed but not implemented.
- Voice AI depends on cloud connectivity and LLM API quotas.

## 17. Future Scope
1. Exotel/Twilio SIP integration with a toll-free number.
2. AIS-140 VLTS integration for real-time fleet tracking (RTDB sharded by state).
3. Conductor dashboard: manifest, halt trigger, headcount.
4. SMS/USSD gateway on the same engine.
5. Automated voice calls to feature-phone riders for halt alerts.
6. Multi-STC datasets (KSRTC, GSRTC, UPSRTC…).
7. Predictive delay ML from historical GPS.
8. UPI ticketing with STC settlement.
9. Admin analytics dashboard (call sentiment, route demand heatmaps).

## 18. Conclusion
BussPass shows that public-transport information can be **accurate, offline, multilingual, and humane**. By pairing a rigorous transit engine with an empathetic AI voice officer, it reaches every rider, whether they carry a flagship iPhone or a basic keypad phone, and gives STCs a scalable, low-cost path to modern passenger services.

## 19. Appendix: Repository Map

```
SIH-BussPass/
├── busspass/                    Flutter app (Android + iOS)
│   ├── lib/core/math/           journey_planner, fare_engine, eta_engine, occupancy, geo, schedule
│   ├── lib/core/services/       bus_simulator, transit_detection, notification, directions, state_detection, travel_pattern_alerts
│   ├── lib/data/                models, providers, repositories
│   ├── lib/features/            onboarding, dashboard, home, journey, timetable, state
│   └── assets/                  data/network.json, translations/
├── scripts/                     build_dataset, seed_firestore, process_trip_master, upload_images, verify_seed …
├── msrtc_human_ai_agent.py      Voice AI engine (tools, persona, CRM, emergency)
├── ivr_simulator_gui.py         Desktop IVR simulator
├── adk_live_voice.py            Headless live voice agent
├── AI_HUMAN_IVR_ARCHITECTURE.md
├── ARCHITECTURE.md
├── BussPass_Implementation_Plan.md
└── README.md
```
