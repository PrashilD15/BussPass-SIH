# BussPass — Product Requirements Document (PRD)

| Field | Value |
|---|---|
| Product | **BussPass — Your Travel Partner** |
| Event | Smart India Hackathon (SIH) 2026-27 |
| Primary Client | State Transport Corporations (MSRTC first; KSRTC, GSRTC, etc. registered) |
| Platforms | Android · iOS · Feature/Keypad phone (Voice AI IVR) |
| Document Version | 1.0 |
| Date | 09 Oct 2026 |
| Status | Prototype built; production roadmap defined |

---

## 1. Executive Summary

India's state transport corporations carry **~70 million passengers every day**, but riders still depend on faded notice boards, word of mouth, and enquiry counters. BussPass is a **multi-channel public-transport companion** that offers:

1. A **Flutter mobile app** (Android + iOS) with offline journey planning, official fares, traffic-aware ETAs, live tracking, and QR tickets/passes.
2. An **AI "Human" Enquiry Officer** — a voice agent over the phone that speaks Marathi, Hindi, and English. It works on any phone, including a ₹1,500 keypad handset, with no app and no internet needed on the caller's side.

The core idea: **one offline transit engine serves every channel**. The app, the voice IVR, and the planned SMS/USSD gateway all use the same network graph and the same algorithms.

---

## 2. Problem Statement

| # | Pain Point | Real-World Impact |
|---|---|---|
| P1 | No multi-bus journey planner | Village-to-village trips need 2–3 changes that riders must work out by asking strangers |
| P2 | Fares are opaque | Confusion between Ordinary, Shivshahi, and Shivneri, and concession eligibility |
| P3 | No offline access | Rural stands with poor coverage get no digital help at all |
| P4 | Language exclusion | English-first apps exclude Marathi, Hindi, and Kannada speakers |
| P5 | Feature-phone / elderly exclusion | 300M+ feature-phone users and non-literate elders can't use apps |
| P6 | Night-halt stranding | Passengers get left behind at meal halts on overnight buses |
| P7 | Missed stops | No "your stop is coming" alert on long or night journeys |
| P8 | Robotic IVRs | "Press 1… Invalid option… Goodbye" frustrates callers, especially elders |
| P9 | Fake "live" tracking | Some apps show hardcoded positions and erode trust |
| P10 | Paper tickets | Easily lost, no history, no digital validation |

---

## 3. Goals & Non-Goals

### 3.1 Goals
- **G1**: Plan any stop-to-stop journey (including transfers) in under 1 second, fully offline.
- **G2**: Show **official MSRTC stage fares** with concessions applied.
- **G3**: Give realistic ETAs that account for traffic, dwell time, and meal halts.
- **G4**: Serve non-smartphone users through a **natural-language voice AI** in their native language.
- **G5**: Keep riders safe with arrival, halt, and delay alerts, plus emergency help on calls.
- **G6**: Support multiple states automatically through GPS-based STC detection.

### 3.2 Non-Goals (current phase)
- Online payment settlement with STC treasury systems (ticket and payment models exist; settlement is out of scope).
- Building physical GPS hardware at scale (the prototype uses a deterministic simulator; hardware is a provider swap).
- Seat reservation and inventory management (MSRTC's existing system covers this).

---

## 4. Target Users & Personas

| Persona | Profile | Channel | Key Need |
|---|---|---|---|
| **Priya**, 21, student, Pune | Android, data plan | App | Cheapest daily route, student concession, pass |
| **Ramesh-kaka**, 68, farmer, Sangamner | Keypad phone, Marathi only | Voice AI IVR | "When is the next bus to Nashik, and from which platform?" |
| **Anil**, 35, IT engineer, Thane | iPhone | App | Fast ETAs and live tracking on the expressway |
| **Sunita**, 45, night traveller | Android | App + IVR | Halt alerts and safety/emergency help |
| **Conductor** | MSRTC POS device | POS / Dashboard (planned) | Headcount at halts, link passenger phone to ticket |
| **STC Administrator** | Desktop | Firestore / Admin tooling | Update timetables and fares, monitor fleet |

---

## 5. Functional Requirements

### 5.1 Mobile App (Android + iOS)

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-01 | Language selection (en / mr / hi / kn), persisted across restarts | P0 | ✅ Built |
| FR-02 | Google Sign-In via Firebase Auth | P0 | ✅ Built |
| FR-03 | GPS-based automatic state/STC detection (offline bounding-box table) | P1 | ✅ Built |
| FR-04 | Journey search by origin/destination stop and departure time | P0 | ✅ Built |
| FR-05 | Time-dependent Dijkstra planner: up to 3 transfers, 10-min min transfer, 25-min penalty, walk links ≤ 1.5 km | P0 | ✅ Built |
| FR-06 | Up to 4 diversified results (fastest, cheapest, fewest changes, guaranteed direct) | P0 | ✅ Built |
| FR-07 | MSRTC stage-fare engine (8 bus classes, 6 concession categories) | P0 | ✅ Built |
| FR-08 | ETA engine (trip length, time of day, stop density, dwell, meal halts, traffic factor) | P0 | ✅ Built |
| FR-09 | Occupancy indicator: reported (POS) vs. modelled, clearly labelled | P1 | ✅ Built |
| FR-10 | Live map with fleet of up to 220 buses on real polylines | P0 | ✅ Built (simulated feed) |
| FR-11 | Walk-to-stand navigation (OSRM walking polyline) when > 100 m away | P1 | ✅ Built |
| FR-12 | Live navigation with road-snapped polyline, real GPS, ETA recalculation | P0 | ✅ Built |
| FR-13 | Transit detection (4-step decision tree on GPS trail) | P1 | ✅ Built |
| FR-14 | OS notifications across arrival / halt / delay / journey channels | P0 | ✅ Built |
| FR-15 | Travel-pattern alerts (auto-remind for repeated O-D searches) | P2 | ✅ Built |
| FR-16 | Digital QR tickets and time-bound passes, viewable offline | P0 | ✅ Built |
| FR-17 | QR scanner for conductor validation | P1 | ✅ Built |
| FR-18 | Timetable viewer (nearest departure first + search) | P1 | ✅ Built |
| FR-19 | Light (Saffron Dawn) / Dark (Midnight Indigo) / System theme | P2 | ✅ Built |
| FR-20 | Accessibility: larger text (1.0–1.4×), reduce motion, WCAG AA contrast | P1 | ✅ Built |

### 5.2 AI Human Voice IVR

| ID | Requirement | Priority | Status |
|---|---|---|---|
| FR-21 | Real-time bidirectional voice conversation (Gemini Live via Google ADK) | P0 | ✅ Prototype |
| FR-22 | Greets in Hindi first; offers Marathi/English; handles code-switching | P0 | ✅ Prototype |
| FR-23 | Tool: `get_top3_upcoming_buses` — 3 nearest departures from the current clock, with platform, type, and fare | P0 | ✅ Built |
| FR-24 | Tool: `get_route_details` / `get_fare_details` — via-stops, duration, fare by bus type | P0 | ✅ Built |
| FR-25 | Tool: `get_live_bus_eta` — live position / ETA for a bus number | P1 | ✅ Built |
| FR-26 | Tool: `get_caller_ticket` — auto-fetch active ticket by caller ID | P1 | ✅ Built |
| FR-27 | Caller CRM: remembers name, language, mood, frequent routes (`caller_profiles`) | P1 | ✅ Built |
| FR-28 | Emergency handling: Accident / Unsafe / Medical / Breakdown / Fire / Missing → 112, 108, 1091, MSRTC control room | P0 | ✅ Built |
| FR-29 | Desktop IVR simulator with dial pad, DTMF, mic, and call recording | P1 | ✅ Built |
| FR-30 | IoT hardware trigger: incoming call via Firestore `ivr_gateway/current_call` | P2 | ✅ Built |
| FR-31 | PSTN/SIP gateway (Exotel / Twilio) to WebSocket AI server | P1 | 🟡 Planned |

### 5.3 Platform & Data

| ID | Requirement | Status |
|---|---|---|
| FR-32 | Offline `network.json` (91 stops, 273 routes, 602 services, 5,494 departures, ~439 KB) | ✅ Built |
| FR-33 | Data pipeline: scrape, merge official Trip Master (XLSX), build graph, seed Firestore | ✅ Built |
| FR-34 | Firestore real-time overlay on top of the offline bundle | ✅ Built |
| FR-35 | Firebase Storage per-bus-type photos | ✅ Built |
| FR-36 | Route cache (distributed memoization) in Firestore | ✅ Designed |
| FR-37 | SMS/USSD gateway (`*789*<from>*<to>#`) reusing the same graph | 🟡 Planned |
| FR-38 | Conductor dashboard: manifest, headcount, halt trigger | 🟡 Planned |

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Performance** | Offline route search < 1 s on mid-range Android; map tick every 3 s for 220 buses |
| **Offline** | Search, fares, timetables, and tickets work with zero connectivity |
| **Voice latency** | First audio response ≤ 1.5 s after the caller finishes speaking (streaming) |
| **Availability** | Target 99.5% for the IVR backend (multi-region in production) |
| **Scalability** | Firestore/RTDB sharded by state; Cloud Functions scale horizontally |
| **Security** | No secrets in source; `.env` and service account keys git-ignored; Firestore rules per collection |
| **Privacy** | DPDP Act 2023: rider location processed in memory; caller data minimised; 24-hour location purge |
| **Accessibility** | WCAG AA; text scale up to 1.4×; voice-first channel for non-literate users |
| **Localization** | 4 app languages; 3 voice languages with dialect and code-switch tolerance |
| **Reliability** | Notification and permission failures never crash the app (failure-tolerant services) |
| **Determinism** | Simulator and planner are deterministic, so results are reproducible and testable |

---

## 7. ⭐ Unique Selling Points (USPs)

| # | Unique Point | Why It Matters |
|---|---|---|
| U1 | **"AI Human" Enquiry Officer instead of a menu IVR** | Empathetic persona ("Sunita Madam" / "Aapli ST Helpdesk Officer"): acknowledges intent first, never says "Invalid option", talks like a family member |
| U2 | **Works on a ₹1,500 keypad phone** | The voice channel needs no app, no data, and no literacy, reaching 300M+ excluded users |
| U3 | **Caller-ID context pre-fetch** | The AI knows the caller's active ticket and history *before they speak* |
| U4 | **Top-3 nearest departures, not 50 timings** | Computes from the live clock and speaks platform/bay, bus type, fare, and deboarding stand |
| U5 | **Code-switch and spoken-number understanding** | "संगमनेर से नाशिक बस वेळ काय आहे?" and "बारा चौतीस" = 1234 |
| U6 | **Caller CRM memory** | Greets repeat callers by name in their language and suggests frequent routes |
| U7 | **Built-in emergency triage on calls** | Detects accident/medical/harassment and routes to 112/108/1091 and the MSRTC control room |
| U8 | **One offline engine, three channels** | The same graph and algorithms power the app, IVR, and SMS/USSD, so answers stay consistent everywhere |
| U9 | **Time-dependent Dijkstra over stops (not cities)** | Reaches villages that buses merely pass through; never proposes impossible connections |
| U10 | **Official MSRTC stage-fare model (18 Jul 2026)** | 8 bus classes, 6 real concessions (Mahila Samman 50%, Senior 65+ free, etc.) |
| U11 | **Physics-style ETA model** | Trip length, peak hours, stop density, 70 s dwell, explicit meal halts; calibrated within minutes on Mumbai–Pune and Pune–Nashik |
| U12 | **Honest occupancy labelling** | "Reported" (POS ground truth) vs. "Estimated", so riders are never misled |
| U13 | **Deterministic fleet simulator** | Position = f(service, departure, clock), reproducible and testable; swapping to real GPS is a provider change only |
| U14 | **4-step transit detection** | Detects whether the rider is on a bus and which one, using sustained-window thresholds that resist GPS noise |
| U15 | **Night-halt safety alerts** | A dedicated OS channel warns riders before the bus leaves a meal halt |
| U16 | **Travel-pattern learning** | Searching the same route twice schedules a reminder 20 min before the next departure, with no spam |
| U17 | **Auto state/STC detection offline** | GPS bounding box, no API call; theme and brand colour change per STC |
| U18 | **Zero placeholder data** | Every number comes from a real engine or real dataset (official Trip Master XLSX merged) |
| U19 | **AIS-140 VLTS Integration** | Ingests existing STC AIS-140 VLTS feeds instead of custom hardware |
| U20 | **Inclusive design** | Dark mode built from semantic roles, 1.4× text, reduce-motion, 4 languages |

---

## 8. Success Metrics (KPIs)

| KPI | Target (Pilot, 6 months) |
|---|---|
| Monthly active app users | 1 lakh in the Ahilyanagar/Pune division |
| IVR calls resolved without a human | ≥ 80% |
| Avg. IVR call duration | ≤ 90 seconds |
| Journey planner "no route" rate (where a route exists) | < 1% |
| ETA accuracy | ±10 min on 85% of trips |
| Halt-stop stranding incidents | −90% on piloted routes |
| Crash-free sessions | ≥ 99.5% |
| Accessibility usage (large text / voice) | Tracked and reported |

---

## 9. Release Plan

| Phase | Scope |
|---|---|
| **v1.0 (SIH prototype)** | App (all FR-01 → FR-20), Voice AI simulator, offline dataset, Firestore overlay |
| **v1.1 (Pilot)** | Exotel/Twilio telephony, AIS-140 VLTS feed for 50 buses, conductor halt button |
| **v1.2** | SMS/USSD gateway, conductor dashboard, route cache, FCM push |
| **v2.0 (State rollout)** | Multi-STC datasets, sharded RTDB, adaptive GPS intervals, analytics dashboard for STC |

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Real-time GPS not available at launch | Deterministic simulator on real timetables; provider swap later |
| Timetable data drift | Firestore overlay plus a repeatable pipeline from official Trip Master files |
| Voice AI hallucination | Strict tool-calling; "Zero hardcoded fallbacks"; honest "not found" replies |
| Telephony cost | Toll-free IVR via B2G model; short, efficient AI calls |
| Notification permission denied | Every service is failure-tolerant; the app stays fully usable |
| Secret leakage | Keys moved to `.env` / secret manager; `.gitignore` covers credentials |

---

## 11. Dependencies
Flutter 3.24 · Dart 3.11 · Riverpod · Firebase (Auth, Firestore, Storage, RTDB) · Google Maps SDK · OSRM · easy_localization · flutter_local_notifications · Google ADK + Gemini Live · Edge neural TTS · Node.js 18 pipeline · Python 3 (IVR, data processing).
