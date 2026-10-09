---
pdf_options:
  format: A4
  margin: 20mm
  printBackground: true
  displayHeaderFooter: true
  headerTemplate: '<div style="font-size:8px; width:100%; text-align:center; color:#888; padding-top:5mm;">BussPass — SIH 2026 Implementation Plan (Confidential)</div>'
  footerTemplate: '<div style="font-size:8px; width:100%; text-align:center; color:#888; padding-bottom:5mm;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: pdf-body
---

<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap');

  body {
    font-family: 'Inter', -apple-system, sans-serif;
    color: #1a1a2e;
    line-height: 1.7;
    font-size: 11px;
  }

  h1 {
    font-size: 28px;
    font-weight: 900;
    color: #0f0f23;
    border-bottom: 3px solid #4361ee;
    padding-bottom: 10px;
    margin-top: 40px;
  }

  h2 {
    font-size: 18px;
    font-weight: 700;
    color: #1a1a2e;
    margin-top: 30px;
    border-left: 4px solid #4361ee;
    padding-left: 12px;
  }

  h3 {
    font-size: 14px;
    font-weight: 600;
    color: #2d2d44;
    margin-top: 20px;
  }

  h4 {
    font-size: 12px;
    font-weight: 600;
    color: #4361ee;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 10px;
  }

  th {
    background: #4361ee;
    color: white;
    padding: 8px 10px;
    text-align: left;
    font-weight: 600;
  }

  td {
    padding: 6px 10px;
    border-bottom: 1px solid #e0e0e0;
  }

  tr:nth-child(even) td {
    background: #f8f9ff;
  }

  code {
    background: #f0f0f5;
    padding: 1px 5px;
    border-radius: 3px;
    font-size: 10px;
    font-family: 'JetBrains Mono', 'Fira Code', monospace;
  }

  pre {
    background: #1a1a2e;
    color: #e0e0e0;
    padding: 14px;
    border-radius: 8px;
    font-size: 9.5px;
    overflow-x: auto;
    line-height: 1.5;
  }

  pre code {
    background: transparent;
    color: inherit;
    padding: 0;
  }

  blockquote {
    border-left: 4px solid #4361ee;
    margin: 14px 0;
    padding: 10px 16px;
    background: #f0f4ff;
    border-radius: 0 6px 6px 0;
    font-size: 10.5px;
  }

  .cover-page {
    text-align: center;
    padding: 80px 0 40px 0;
    page-break-after: always;
  }

  .cover-page h1 {
    font-size: 42px;
    border: none;
    color: #4361ee;
    margin-bottom: 5px;
  }

  .cover-page .subtitle {
    font-size: 16px;
    color: #555;
    margin-bottom: 40px;
    font-weight: 300;
  }

  .cover-page .tagline {
    font-size: 13px;
    color: #333;
    max-width: 500px;
    margin: 0 auto 50px auto;
    line-height: 1.8;
    font-style: italic;
  }

  .cover-page .meta {
    font-size: 11px;
    color: #777;
    margin-top: 60px;
  }

  .highlight-box {
    background: linear-gradient(135deg, #f0f4ff, #e8ecff);
    border: 1px solid #c5d0ff;
    border-radius: 8px;
    padding: 14px 18px;
    margin: 14px 0;
    font-size: 10.5px;
  }

  .warning-box {
    background: #fff8e1;
    border: 1px solid #ffe082;
    border-radius: 8px;
    padding: 14px 18px;
    margin: 14px 0;
    font-size: 10.5px;
  }

  .success-box {
    background: #e8f5e9;
    border: 1px solid #a5d6a7;
    border-radius: 8px;
    padding: 14px 18px;
    margin: 14px 0;
    font-size: 10.5px;
  }

  hr {
    border: none;
    border-top: 2px solid #e8ecff;
    margin: 25px 0;
  }

  ul, ol {
    padding-left: 20px;
  }

  li {
    margin-bottom: 4px;
  }
</style>

<div class="cover-page">

# 🚌 BussPass

<div class="subtitle">Smart Transit Companion for Indian State Transport</div>

<div class="tagline">
"Where Is My Bus" — A real-time transit companion for Indian state transport passengers, powered by the STCs' existing AIS-140 Vehicle Location Tracking System (VLTS), and inclusive of elderly & feature-phone users through a Google ADK–powered "AI Human" voice IVR.
</div>

**Implementation Plan & Technical Architecture**

**Smart India Hackathon 2026**

<div class="meta">

**Team:** Beyond Binary

**Date:** October 2026

**Version:** 2.0 (Revised Architecture)

**Classification:** Team Internal — Confidential

</div>

</div>

<div class="success-box">

**📝 Revision Note (v2.0 — October 2026)**

1. **No custom tracking hardware.** v1.0 planned to fit every bus with our own GPS module (NEO-6M + HC-05 Bluetooth) relayed through the conductor's POS. Our research showed that state transport buses **already carry AIS-140 compliant Vehicle Location Tracking Devices (VLTDs)** under the MoRTH mandate for public service vehicles. MSRTC's fleet already reports to the corporation's VLTS / command-and-control backend. BussPass now **integrates with this existing VLTS feed** instead of installing new hardware. The custom GPS + POS relay design has been removed.
2. **IVR rebuilt on Google ADK.** The DTMF menu IVR (Exotel + Sarvam STT/TTS) is replaced by an **"AI Human" Enquiry Officer** built with the **Google Agent Development Kit (ADK)** and **Gemini Live** streaming audio, with tool-calling into our timetable, fare, ticket and live-tracking data.

</div>

# 1. Problem Statement & Context

Indian state transport corporations (MSRTC, KSRTC, UPSRTC, APSRTC, etc.) carry **~70 million passengers daily**, yet passengers have:

- **Zero real-time visibility** into bus locations on most routes
- **No reliable multi-bus journey planning** (unlike "Where is my Train" for railways)
- **No accessibility** for the elderly or feature-phone users (~300M+ users in India)
- **No night-halt alerts** — passengers get stranded at food stops
- **Conductors lack digital headcount** tools for halt-stop management

## 1.1 What Exists vs. What We Build

| Feature | Existing Solutions ("Aapli ST", etc.) | **BussPass (Ours)** |
|---|---|---|
| GPS Tracking | ✅ Basic (16K buses) | ✅ **Consumes the same existing AIS-140 VLTS feed**: no new hardware, plus ETA, transit detection & alerts on top |
| Multi-bus Journey Planning | ❌ Not available | ✅ **Graph-based route planner with real-time ETA** |
| Smart Transit Detection | ❌ Not available | ✅ **Auto-detect if user is inside a bus** |
| Connection Bus Management | ❌ Not available | ✅ **Real-time connecting bus availability** |
| Feature Phone / Elderly Support | ❌ Not available | ✅ **Google ADK "AI Human" voice IVR** (Gemini Live, Marathi/Hindi/English, no menus) |
| Night Halt Alerts | ❌ Not available | ✅ **Push + automated phone call alerts** |
| Conductor Headcount Dashboard | ❌ Not available | ✅ **Digital passenger manifest** |

---

# 2. System Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                 DATA SOURCES (ALL PRE-EXISTING)                      │
│                                                                      │
│  🛰️ AIS-140 VLTD on every bus ──▶ 🏢 STC VLTS / Command Centre ──▶   │
│     (mandated, already fitted)       (API / data-sharing feed)       │
│  📋 Official timetables / Trip Master   🎫 STC ticketing (ETIM) data  │
└──────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                  🔌 BussPass VLTS Integration Adapter
             (pull/push ingest → normalise → map to route/service)
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    BACKEND (Firebase + Cloud)                        │
│                                                                      │
│  🔥 Firebase RTDB          📦 Firestore          ⚡ Cloud Functions  │
│  (Bus Locations -          (Routes, Stops,       (ETA Engine,        │
│   real-time sync)           Schedules, Tickets)   Alerts, IVR)       │
│         │                        │                      │            │
│         └────────────────────────┼──────────────────────┘            │
│                                  │                                   │
│              🧠 Google ADK Agent + Gemini Live                       │
│        (AI Human IVR: streaming voice, tool-calling)                 │
└──────────────────────────────────────────────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  📱 Flutter App  │  │ 📞 AI Human IVR  │  │ 👨‍✈️ Conductor    │
│  (iOS + Android) │  │  (Google ADK +   │  │   Dashboard      │
│  - Live tracking │  │   Gemini Live)   │  │  (Flutter Web)   │
│  - Journey plan  │  │  - Free speech   │  │  - Headcount     │
│  - Transit detect│  │  - Tool calling  │  │  - Halt alerts   │
│  - Halt alerts   │  │  - mr / hi / en  │  │  - Passenger list│
└──────────────────┘  └──────────────────┘  └──────────────────┘
    Smartphone             Feature Phone        Phone / Tablet
    Users                  & Elderly Users       Conductors
```

---

# 3. Technology Stack

## 3.1 Mobile App (Passengers + Conductor)

| Layer | Technology | Justification |
|---|---|---|
| **Framework** | **Flutter 3.x** (Dart) | Single codebase → iOS + Android + Web |
| **State Management** | **Riverpod 2.x** | Reactive, testable, clean architecture |
| **Maps** | **Google Maps Flutter** | Best India coverage, traffic layer, polylines |
| **Location** | `geolocator` + `flutter_background_service` | Background location for transit detection |
| **Notifications** | Firebase Cloud Messaging (FCM) | Push alerts for halt stops, ETA reminders |
| **Local DB** | **Hive** or **Isar** | Offline route cache for low-connectivity areas |

## 3.2 Backend

| Layer | Technology | Justification |
|---|---|---|
| **Real-time DB** | **Firebase Realtime Database** | Ultra-low latency (~200ms) for live bus positions |
| **Persistent DB** | **Cloud Firestore** | Routes, stops, schedules, tickets, user journeys |
| **Serverless** | **Firebase Cloud Functions (TypeScript)** | ETA calculations, alerts, IVR webhooks |
| **AI/ML** | **Google ADK + Gemini Live** | AI Human IVR agent: streaming speech in/out, intent understanding, tool-calling |
| **Tracking Ingest** | **VLTS Integration Adapter** (Cloud Functions / Cloud Run) | Pulls or receives the STC's existing AIS-140 VLTS feed and writes to RTDB |
| **Auth** | **Firebase Auth** | Phone OTP (works with all Indian numbers) |
| **Hosting** | **Firebase Hosting** | Admin dashboard, conductor web app |

## 3.3 AI Human IVR System (Google ADK)

| Layer | Technology | Justification |
|---|---|---|
| **Agent Framework** | **Google Agent Development Kit (ADK)**: `Agent`, `Runner`, `LiveRequestQueue`, session service | Production-grade agent orchestration, native tool-calling, live bidirectional streaming |
| **Model** | **Gemini Live** (native audio) | Speech understanding + generation in one streaming model; handles Marathi/Hindi/English code-switching and spoken numbers |
| **Tools** | Python functions in `msrtc_human_ai_agent.py` | `get_top3_upcoming_buses`, `get_route_details`, `get_fare_details`, `get_live_bus_eta`, `get_caller_ticket`, `get_caller_profile` / `update_caller_profile`, `handle_emergency` |
| **Telephony** | SIP / media-stream bridge (Exotel / Twilio / Asterisk), planned | Bridges PSTN calls from feature phones into the ADK live session over WebSocket |
| **Prototype front-end** | `ivr_simulator_gui.py` (Tkinter) + `adk_live_voice.py` (headless) | Dial pad, DTMF, live mic, call recording, Firestore IoT call trigger |
| **Fallback TTS** | Neural TTS (e.g. `en-IN-NeerjaNeural`) | Text-mode / CLI responses |

## 3.4 Vehicle Tracking — Existing AIS-140 VLTS (No New Hardware)

| Item | Detail |
|---|---|
| **Source** | AIS-140 compliant VLTD already fitted on STC buses (MoRTH mandate for public service vehicles), reporting to the STC's VLTS / command-and-control centre |
| **Data available** | Vehicle reg. no., lat/lng, speed, heading, timestamp, ignition / status, emergency (panic) button events |
| **Access** | Data-sharing agreement with the STC → REST pull, push webhook or MQTT/stream from the VLTS backend |
| **BussPass component** | **VLTS Integration Adapter**: authenticates, ingests, de-duplicates, map-matches each vehicle to its route/service (from schedule/duty data), writes to RTDB `buses/{busId}` |
| **Hardware cost to BussPass** | **₹0.** No GPS modules, Bluetooth links or POS apps to install or maintain |
| **Prototype** | Deterministic `BusSimulator` produces the identical `LiveBus` model until the live feed is connected (a provider swap only) |

---

# 4. Feature Modules — Detailed Design

## 4.1 🗺️ Real-Time Bus Tracking ("Where is my Bus")

### Firebase RTDB Schema

```json
{
  "buses": {
    "MH12AB1234": {
      "lat": 18.5204,
      "lng": 73.8567,
      "speed": 45.2,
      "heading": 180,
      "routeId": "PUNE-MUM-001",
      "nextStopId": "LONAVALA",
      "etaNextStop": 1724700000,
      "status": "IN_TRANSIT",
      "lastUpdated": 1724699500,
      "passengerCount": 38
    }
  }
}
```

### How It Works

1. The AIS-140 VLTD already installed on the bus reports position to the STC's VLTS backend (no BussPass hardware involved)
2. The **VLTS Integration Adapter** pulls (or receives a push of) the latest positions from the STC VLTS API
3. The adapter normalises each record, map-matches the vehicle to its active route/service, and writes `{lat, lng, speed, heading, routeId, nextStopId, lastUpdated}` to `buses/{busId}` in RTDB
4. The Flutter app subscribes via a Riverpod stream → map marker moves in real time
5. `EtaEngine` + Cloud Function compute ETA to the next stops from speed + route geometry; the IVR tool `get_live_bus_eta` reads the same node

### Why reuse the existing VLTS?

- **Already mandated and installed**: no procurement, fitting, wiring or maintenance
- **Single source of truth**: the same positions the STC control room sees
- **Instant scale**: every VLTS-equipped bus is trackable as soon as the feed is connected
- **Safety signal included**: AIS-140 panic-button events can be surfaced to the control room / IVR emergency flow

---

## 4.2 🔀 Multi-Bus Journey Planner

### Core Algorithm: Modified Dijkstra on Transit Graph

```
Input:  Source Stop, Destination Stop, Departure Time
Output: Ordered list of [Bus, Board Stop, Alight Stop, ETA]

Algorithm:
1. Build weighted directed graph:
   - Nodes = All bus stops
   - Edges = Direct bus connections (weight = travel time)
   - Transfer edges = Walking between nearby stops
     (weight = walk time + estimated wait time)

2. Run time-dependent Dijkstra:
   - At each node, check which buses are AVAILABLE at that time
   - Query RTDB (fed by the existing VLTS) for real-time bus positions for actual ETA
   - Factor in buffer time for connections (minimum 10 min)

3. Return top 3 routes ranked by:
   - Total travel time
   - Number of changes required
   - Reliability score (based on bus punctuality data)
```

### Firestore Route Schema

```json
{
  "routes/PUNE-MUM-001": {
    "name": "Pune → Mumbai (via Expressway)",
    "operator": "MSRTC",
    "stops": [
      {"id": "SWARGATE", "name": "Swargate", "lat": 18.5018, "lng": 73.8636, "seq": 1},
      {"id": "LONAVALA", "name": "Lonavala", "lat": 18.7546, "lng": 73.4062, "seq": 3},
      {"id": "DADAR", "name": "Dadar", "lat": 19.0178, "lng": 72.8478, "seq": 8}
    ],
    "schedule": {
      "frequency": "every 30 min",
      "firstBus": "05:00",
      "lastBus": "23:30"
    },
    "avgDuration": 240
  }
}
```

---

## 4.3 📍 Smart Transit Detection

### Detection Logic Flow

```
User location updates (background service, every 30s)
    │
    ▼
Is user speed > 15 km/h for > 2 minutes?
    │
    ├── NO  → Status: STATIONARY
    │
    └── YES → Is location within 50m of any active bus route?
                  │
                  ├── NO  → Status: In private vehicle
                  │
                  └── YES → Does user GPS trail match any bus in RTDB?
                              │
                              ├── NO  → Prompt: "Are you on a bus?"
                              │
                              └── YES → 🎯 Status: ON BUS (Bus ID matched)
                                          │
                                          ▼
                                   Track journey progress
                                   Calculate ETA to destination
                                          │
                                          ▼
                                   Approaching alight stop?
                                          │
                                          └── YES → 🔔 "Your stop is 2 min away!"
```

**Key Technique:** Cross-reference user's GPS trail with bus GPS trail from RTDB. If both are moving along the same route with < 100m deviation for > 3 minutes → user is on that bus.

---

## 4.4 🔗 Connection Bus Management

When a journey requires changing buses:

1. **Pre-departure:** Show all connecting buses at the transfer stop, with real-time ETAs
2. **In-transit:** Continuously recalculate:
   - "You'll reach Lonavala at ~2:30 PM"
   - "Bus to Mumbai departs at 2:45 PM (✅ On time, 15 min buffer)"
   - "Next alternative: 3:15 PM if you miss this one"
3. **Dynamic re-routing:** If the connecting bus is delayed/cancelled, auto-suggest alternatives
4. **Alert:** Push notification 5 min before reaching the transfer stop

---

## 4.5 📞 AI Human IVR for Elderly / Feature Phone Users (Google ADK)

No menus and no "Press 1". The caller simply talks to an empathetic **AI Enquiry Officer** built with the **Google Agent Development Kit (ADK)** and **Gemini Live**.

### Call Flow

```
📞 User dials helpline (any phone — keypad, landline, smartphone)
    │
    ▼
☎️ Telephony bridge / simulator → opens ADK live session (LiveRequestQueue)
    │
    ▼
🔎 Caller-ID pre-fetch: get_caller_profile + get_caller_ticket (Firestore)
    │
    ▼
🗣️ AI Officer greets in Hindi, offers Marathi / English
   (repeat callers greeted by name in their preferred language)
    │
    ▼
🎤 Caller speaks freely (code-switching OK) → streamed to Gemini Live
    │
    ▼
🧠 ADK agent decides & calls tools:
    ├── get_top3_upcoming_buses  → next 3 departures, platform, type, fare
    ├── get_route_details        → via stops, duration
    ├── get_fare_details         → MSRTC stage fare per bus type
    ├── get_live_bus_eta         → live position from VLTS-fed RTDB
    ├── get_caller_ticket        → active ticket by caller ID
    └── handle_emergency         → 112 / 108 / 1091 / MSRTC control room
    │
    ▼
🔊 Natural spoken reply streamed back (native audio)
    │
    ▼
💾 update_caller_profile (name, language, mood, summary) → hang up
```

### Conductor-Assisted Flow (Feature Phone Boarding)

1. Conductor issues a ticket on the STC's existing electronic ticket machine (ETIM) / conductor app
2. Ticket data (with the passenger's phone number) is synced to Firestore through the STC ticketing integration
3. Cloud Function creates a "journey record" linked to that phone number
4. When the elderly person calls the IVR, system looks up their active journey by caller ID
5. IVR tells them: *"You are on Bus MH12AB1234. Next stop: Lonavala in 45 minutes."*

---

## 4.6 🌙 Night Halt Alert System

### Trigger Flow

```
Step 1: Conductor taps "HALT STOP" on the conductor dashboard
        (or halt auto-detected: VLTS shows ignition off / stationary at a known meal-halt stop)
    │
    ▼
Step 2: Cloud Function fires:
    ├── Push notification to all smartphone passengers on this bus
    └── Set 20-minute countdown timer
    │
    ▼
Step 3: After 15 minutes:
    └── "Bus leaving in 5 min" push notification
    │
    ▼
Step 4: After 18 minutes:
    └── Automated outbound call (ADK voice agent via telephony bridge) to feature-phone passengers
        Voice: "Aapki bus 2 minute mein chal rahi hai, kripya wapas aayein"
    │
    ▼
Step 5: Conductor sees headcount dashboard:
    ├── Total passengers: 42
    ├── Confirmed back: 38
    └── ⚠️ Not confirmed: 4 (names + seat numbers highlighted in red)
```

---

## 4.7 👨‍✈️ Conductor Dashboard

| Feature | Description |
|---|---|
| **Passenger Manifest** | Live list of all ticketed passengers with phone numbers |
| **Headcount Tool** | One-tap check-in / check-out for halt stops |
| **Halt Alert Trigger** | Button to initiate halt-stop countdown alerts |
| **Route Progress** | Visual route progress bar with upcoming stops & ETAs |
| **Delayed Bus Flag** | Flag bus as delayed (auto-notifies connecting passengers) |

---

# 5. Complete Data Model

## 5.1 Firestore Collections

```
📦 Firestore
│
├── 👤 users/{userId}
│       ├── name, phone, language, preferredRoutes
│       └── activeJourney: { busId, boardStop, alightStop, status }
│
├── 🚌 routes/{routeId}
│       ├── name, operator, type (ordinary/express/sleeper)
│       ├── stops: [{ id, name, lat, lng, seq, avgDwell }]
│       ├── schedule: { frequency, firstBus, lastBus }
│       └── fare: { perKm, minimum }
│
├── 🚏 stops/{stopId}
│       ├── name, lat, lng, amenities, district
│       └── connectedRoutes: [routeId1, routeId2, ...]
│
├── 🎫 tickets/{ticketId}
│       ├── passengerId, passengerPhone, busId, routeId
│       ├── boardStop, alightStop, fare, issuedAt
│       └── status: "active" | "completed" | "cancelled"
│
├── 📋 journeyPlans/{planId}
│       ├── userId, createdAt
│       ├── legs: [{ routeId, busId, boardStop, alightStop, etaBoard, etaAlight }]
│       └── status: "planned" | "in_progress" | "completed"
│
└── 🔔 haltAlerts/{alertId}
        ├── busId, routeId, stopName, triggeredAt
        ├── resumeAt, conductorId
        └── confirmations: { userId1: true, userId2: false }
```

## 5.2 Firebase RTDB (Real-Time Only)

```
🔥 RTDB
└── buses/{busId}            ← written only by the VLTS Integration Adapter
        ├── lat, lng, speed, heading
        ├── routeId, nextStopId, etaNextStop
        ├── status, lastUpdated, source: "vlts" | "simulator"
        └── passengerCount           (from STC ticketing data when available)
```

---

# 6. Cloud Functions API Design

| Function | Trigger | Description |
|---|---|---|
| `vltsIngest` | Scheduled pull / HTTPS push from STC VLTS | Ingest existing AIS-140 VLTS positions → normalise → map-match → write `buses/{busId}` |
| `onBusLocationUpdate` | RTDB write on `buses/{busId}` | Calculate ETA to next stops, update journey progress |
| `planJourney` | HTTPS callable | Takes src/dest/time → returns optimal routes |
| `detectTransit` | Scheduled (every 30s per active user) | Cross-reference user location with bus locations |
| `triggerHaltAlert` | HTTPS callable (conductor) | Send push notifications + schedule phone calls |
| `ivrMediaStream` | WebSocket (telephony media stream) | Bridge call audio ↔ Google ADK `Runner.run_live` session (Gemini Live) |
| `ivrTools` | Invoked by ADK agent | Timetable, fare, route, live ETA, ticket, caller CRM, emergency tools |
| `linkTicketToPhone` | Firestore `tickets/{id}` create | Auto-create journey record for feature phone users |
| `connectionMonitor` | Pub/Sub (every 60s) | Check connecting bus availability for transit users |

---

# 7. Existing VLTS Integration Detail

## 7.1 VLTS Integration Adapter Architecture

```
┌──────────────────────────┐      ┌──────────────────────────────┐
│ AIS-140 VLTD on each bus │ ───▶ │ STC VLTS / Command Centre    │
│ (already installed)      │ GSM  │ (existing, operated by STC)  │
└──────────────────────────┘      └──────────────┬───────────────┘
                                                 │ API / webhook / MQTT
                                                 │ (data-sharing agreement)
                                                 ▼
                         ┌──────────────────────────────────────────┐
                         │   BussPass VLTS Integration Adapter      │
                         │   (Cloud Functions / Cloud Run)          │
                         │  • Auth + rate-limited pull / push recv  │
                         │  • De-dupe, drop stale / invalid fixes   │
                         │  • Map vehicle → route/service (duty)    │
                         │  • Snap to route polyline, next stop     │
                         │  • Write buses/{busId} to RTDB           │
                         └───────────────┬──────────────────────────┘
                                         ▼
             ┌──────────────┬────────────┴────────────┬──────────────┐
             ▼              ▼                         ▼              ▼
        Flutter app   Transit detection        ADK IVR tool     Halt / delay
        live map      (rider ↔ bus match)     get_live_bus_eta     alerts
```

## 7.2 Provider Abstraction

The app consumes a single `LiveBus` model. Two interchangeable providers produce it:

| Provider | When used |
|---|---|
| `VltsLiveBusProvider` | Production: STC VLTS feed via RTDB |
| `BusSimulator` (deterministic) | Prototype / demo / fallback if the feed is unavailable |

<div class="highlight-box">

**💡 Key Advantage:** Because the tracking hardware already exists on every bus by regulation, BussPass needs **zero hardware procurement or installation**. Rollout to a new depot or state is a **data-integration task, not a fitting task**.

</div>

---

# 8. Security Architecture

| Layer | Measure |
|---|---|
| **Firebase Auth** | Phone OTP authentication for all users |
| **RTDB Rules** | Only the VLTS Integration Adapter (service account) can write; users read-only |
| **Firestore Rules** | Users read own journeys only; Conductors write own bus data |
| **API Security** | Cloud Functions behind Firebase App Check (device attestation) |
| **VLTS Feed Auth** | STC-issued API credentials stored in Secret Manager, IP allow-listed, rotated per agreement |
| **IVR** | Caller ID verification; ADK tools scoped to read-only data except caller profile; Gemini API key in Secret Manager / env (never in source) |
| **Data Privacy** | Location data auto-deleted after 24h; anonymized for analytics |
| **Compliance** | DPDP Act 2023 compliant — no permanent location storage |

---

# 9. Prototype Scope — SIH 36-Hour Build

<div class="warning-box">

**⚠️ For SIH, we build a working MVP, not a production system.** The following is scoped for the 36-hour hackathon with a 6-member team.

</div>

## 9.1 Must-Have Features (Demo-Ready)

| # | Feature | Priority | Est. Hours | Owner |
|---|---|---|---|---|
| 1 | Flutter app with Google Maps + live bus markers from RTDB | P0 | 6h | Dev 1 |
| 2 | VLTS adapter interface + deterministic simulator standing in for the live VLTS feed | P0 | 2h | Dev 2 |
| 3 | Multi-bus journey planner with 2-3 demo routes | P0 | 6h | Dev 2 |
| 4 | Smart transit detection (match user location to bus) | P0 | 4h | Dev 3 |
| 5 | Night halt alert (push notification + phone call demo) | P0 | 3h | Dev 3 |
| 6 | AI Human IVR demo with Google ADK + Gemini Live (Hindi/Marathi/English) | P0 | 5h | Dev 4 |
| 7 | Conductor dashboard (web) with headcount | P0 | 4h | Dev 5 |
| 8 | Connection bus management UI | P1 | 3h | Dev 5 |
| 9 | Beautiful UI/UX with animations + pitch deck | P0 | 3h | Dev 6 |

**Total: ~36 hours** (6 team members × 6 hours each)

## 9.2 Nice-to-Have (If Time Permits)

| Feature | Notes |
|---|---|
| Live VLTS sample feed | If STC shares a sandbox / sample VLTS endpoint, show real buses |
| Offline mode with Hive caching | For low-connectivity demo scenario |
| Kannada in IVR | Hindi + Marathi + English already supported |
| Analytics dashboard | Show bus utilization, delay patterns |

---

# 10. Project Structure

```
busspass/
├── android/ & ios/
├── web/                          # Conductor dashboard
├── lib/
│   ├── main.dart
│   ├── app.dart                  # MaterialApp, routing, theme
│   ├── core/
│   │   ├── constants/            # Colors, strings, API keys
│   │   ├── theme/                # App theme, typography
│   │   ├── utils/                # Helpers, formatters
│   │   └── services/
│   │       ├── location_service.dart
│   │       ├── notification_service.dart
│   │       └── transit_detection_service.dart
│   ├── data/
│   │   ├── models/               # Bus, Route, Stop, Ticket, Journey
│   │   ├── repositories/        # FirebaseRepo, LocationRepo
│   │   └── providers/           # Riverpod providers
│   ├── features/
│   │   ├── home/                 # Home screen with map
│   │   ├── tracking/            # Live bus tracking screen
│   │   ├── journey_planner/     # Source → Dest planner
│   │   ├── transit/             # In-transit journey view
│   │   ├── connections/         # Connecting bus info
│   │   ├── alerts/              # Halt stop alerts
│   │   ├── conductor/           # Conductor dashboard
│   │   └── onboarding/          # Auth + onboarding
│   └── widgets/                  # Shared UI components
├── functions/                    # Firebase Cloud Functions
│   └── src/
│       ├── eta.ts
│       ├── journey-planner.ts
│       ├── halt-alerts.ts
│       ├── vlts-ingest.ts       # Existing AIS-140 VLTS feed adapter
│       ├── transit-detection.ts
│       └── connection-monitor.ts
├── ivr/                          # Google ADK AI Human IVR (Python)
│   ├── msrtc_human_ai_agent.py  # Tools, persona, CRM, emergency
│   ├── ivr_simulator_gui.py     # Desktop call simulator
│   └── adk_live_voice.py        # Headless live voice agent
├── scripts/
│   └── seed_routes.py           # Seed Firestore with demo data
└── pubspec.yaml
```

---

# 11. Sprint Plan (Pre-SIH 4-Week Preparation)

## Phase 1: Foundation (Week 1)
- [ ] Set up Flutter project with clean architecture (Riverpod)
- [ ] Set up Firebase project (RTDB + Firestore + Auth + Functions)
- [ ] Design app theme, design system, custom widgets
- [ ] Implement Firebase Auth (Phone OTP)
- [ ] Create all data models (Bus, Route, Stop, Ticket, Journey)
- [ ] Seed Firestore with 5-10 demo routes (MSRTC Pune-Mumbai corridor)

## Phase 2: Core Features (Week 2)
- [ ] Build real-time map with live bus markers (RTDB → Google Maps)
- [ ] Define VLTS adapter contract + deterministic simulator provider (moves bus along route polyline)
- [ ] Implement journey planner algorithm (graph-based Dijkstra)
- [ ] Build journey planner UI (source/dest input → route option cards)
- [ ] Implement smart transit detection background service
- [ ] Build in-transit journey view (progress bar, ETA, next stop alert)

## Phase 3: IVR + Conductor (Week 3)
- [ ] Build Google ADK agent (persona + tools) on Gemini Live
- [ ] Implement IVR tools (timetable, fare, route, live ETA, ticket, CRM, emergency)
- [ ] Build desktop IVR simulator + telephony media-stream bridge design
- [ ] Build conductor dashboard (Flutter Web)
- [ ] Implement night halt alert system (push + phone call)
- [ ] Implement connection bus monitoring logic

## Phase 4: Polish + Demo Prep (Week 4)
- [ ] End-to-end integration testing (all features working together)
- [ ] UI polish — animations, transitions, error handling, edge cases
- [ ] Build and rehearse demo script (8-minute time limit)
- [ ] Request VLTS sample feed / API documentation from STC
- [ ] Create pitch deck (PPT/Google Slides)
- [ ] Prepare and rehearse judge Q&A answers

---

# 12. Scalability & Production Roadmap

| Metric | Prototype (SIH) | Production (Post-SIH) |
|---|---|---|
| Buses tracked | 220 (simulated) | Entire VLTS-equipped STC fleet (50,000+) |
| Concurrent users | 100 | 10M+ |
| RTDB architecture | Single instance | Sharded by state/region |
| Journey planner | In-memory graph | Redis-cached + pre-computed |
| IVR capacity | ADK desktop simulator | Autoscaled ADK workers behind SIP bridge, multi-region |
| Position update interval | Simulator 3 s tick | As provided by STC VLTS (AIS-140 reporting interval) |
| Data retention | 24 hours | 90 days (cold storage) |

---

# 13. Judge Q&A Preparation

<div class="warning-box">

**⚠️ CRITICAL SECTION — Every team member must memorize these answers.**

</div>

## Technical Feasibility

**Q: Where does your live bus location come from? Do you install hardware?**

> No new hardware. State transport buses already carry **AIS-140 compliant vehicle tracking devices** under the MoRTH mandate, and these report to the STC's VLTS / command centre. BussPass connects to that existing feed through a **VLTS Integration Adapter** and adds journey planning, ETAs, transit detection, alerts and the voice IVR on top.

**Q: What if the VLTS feed is delayed or a bus stops reporting?**

> The adapter marks stale positions. The app shows "Last updated X minutes ago" and falls back to the **timetable-based ETA model** (`EtaEngine`) for that bus. The deterministic simulator uses the same `LiveBus` model, so the UI never breaks.

**Q: How do you handle the latency of real-time tracking?**

> VLTD → STC VLTS (device reporting interval) → adapter ingest → RTDB (~200 ms) → clients (~100 ms). Our added latency is **well under 2 seconds** on top of the device's own reporting interval.

**Q: Can your system work in areas with poor connectivity (ghats, rural)?**

> Three layers of resilience: (1) the VLTD buffers and the STC backend handles device-side gaps, (2) the Flutter app plans journeys **fully offline** from a bundled network graph and caches last known positions, (3) the AI IVR is reached by an ordinary phone call, so it works even on 2G where mobile data fails.

## Innovation & Novelty

**Q: How is this different from the existing "Aapli ST" app?**

> Aapli ST is GPS tracking only. BussPass adds: (1) Multi-bus journey planning with real-time connections, (2) IVR for 300M+ feature phone users, (3) Smart transit detection, (4) Night halt alerts, (5) Conductor headcount tools. We solve the **accessibility gap** that no existing solution addresses.

**Q: Why not just use the driver's phone or your own GPS device?**

> Drivers change shifts and phones die, and fitting our own devices would duplicate what is already mandated. The AIS-140 VLTD is **hardwired, tamper-monitored and already installed**, so reusing it gives reliable uptime with **zero hardware cost** and no human dependency.

## Scalability

**Q: Can this scale to all of India's 1.5 lakh state transport buses?**

> Firebase RTDB can be sharded by state/region. Each shard handles ~20,000 buses easily. Cloud Functions and ADK IVR workers auto-scale horizontally. Since tracking reuses the existing VLTS, scaling to a new state is a **data-integration task with no hardware rollout**.

**Q: What about data privacy concerns?**

> User location is processed in-memory only for transit detection, never stored permanently. Bus locations are public data. All personal data encrypted at rest. We comply with India's DPDP Act 2023. Location data auto-purged after 24 hours.

## Impact

**Q: How does the IVR help elderly users who can't read?**

> The IVR is an **AI Human Enquiry Officer** built on **Google ADK + Gemini Live**. An elderly Marathi speaker just calls and says "मला पुण्याहून मुंबईला जायचं आहे". No keypresses are needed. The agent understands the speech directly, calls our timetable tool, and replies in natural Marathi with the next 3 buses, platform, bus type and fare. It's **conversational**, not menu-driven.

**Q: What if the elderly person doesn't know the bus number?**

> The passenger's phone number is captured with the ticket at boarding (STC ticketing integration). After that, the IVR automatically identifies their active journey by caller ID. They call and hear: "You are on Bus 1234. Next stop: Lonavala in 45 minutes."

**Q: How do you handle the night halt problem?**

> Conductor triggers halt alert → smartphones get push notification → feature phones get automated call in their language → conductor sees real-time headcount dashboard → after 15 min, final "bus leaving" alert fires. This eliminates passengers being stranded.

## Deployment Model

**Q: How would this be deployed in practice?**

> Primary model is **B2G (Business-to-Government)** — state transport corporations adopt the platform. Live tracking is enabled by connecting to the STC's **existing VLTS feed** under a data-sharing agreement. No hardware is installed. The passenger app is published on Play Store / App Store. IVR number is advertised at bus stands and on tickets.

---

# 14. Demo Script (SIH 8-Minute Presentation)

| Time | Activity | What to Show |
|---|---|---|
| **0:00 - 2:00** | **Problem Statement** | Stats (70M passengers/day), pain points, gap analysis |
| **2:00 - 5:00** | **Live Demo** | |
| | 1. Open app | Live map with 3-4 buses moving in real-time |
| | 2. Plan journey | "Pune to Mumbai" → multi-bus route with connections |
| | 3. Board bus | Transit detection → "You're on Bus MH12-AB-1234" |
| | 4. Connection alert | "Connecting bus at Lonavala departs in 20 min" |
| | 5. Halt stop | Conductor triggers halt → push notification appears |
| | 6. AI Human IVR demo | Live call → speak naturally in Hindi/Marathi → ADK agent answers with next 3 buses |
| **5:00 - 7:00** | **Architecture** | System diagram, existing-VLTS integration (zero hardware), Google ADK IVR flow |
| **7:00 - 8:00** | **Impact & Scale** | National scalability, social inclusion, deployment strategy |

---

# 15. Verification Plan

## Automated Tests
```
flutter test                                    # Unit tests
cd functions && npm test                        # Cloud Function tests
flutter test integration_test/journey_flow.dart # E2E integration
```

## Manual Verification
- Live demo with the simulator provider (and VLTS sample feed, if available) on a physical device
- AI IVR test calls via the ADK desktop simulator (Hindi, Marathi, English, emergency scenarios)
- Multi-device test (passenger app + conductor dashboard simultaneously)
- Offline mode test (airplane mode → reconnect → data sync)
- Night halt alert end-to-end flow (push + phone call)

---

<div style="text-align: center; margin-top: 60px; color: #888; font-size: 10px;">

**BussPass** — Built with ❤️ for 70 Million Daily Passengers

Smart India Hackathon 2026

*This document is confidential and intended for team use only.*

</div>
