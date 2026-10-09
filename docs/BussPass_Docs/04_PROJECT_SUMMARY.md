# BussPass — Project Summary

**Tagline:** *Your Travel Partner — smart journeys for every Indian bus rider, on every phone.*

## The Problem
About 70 million people ride state transport buses in India every day, yet there's no reliable multi-bus planner, fares are opaque, information exists only in English or on paper, and elderly and feature-phone users are shut out of digital tools entirely. Today's IVRs are rigid menus, and night travellers get stranded at meal halts.

## The Solution
BussPass is a **multi-channel transit platform**:

| Channel | Who | What |
|---|---|---|
| 📱 Flutter App (Android + iOS) | Smartphone riders | Offline journey planner, official fares, live map, live navigation, alerts, QR tickets/passes |
| 📞 AI Human Voice Officer | Elderly, non-literate, keypad-phone users | Natural conversation in Marathi/Hindi/English; next 3 buses, platform, fare, ticket status, emergency help |
| ✉️ SMS / USSD (planned) | Basic phones without voice preference | Same engine, text replies |

## Key Numbers

| Metric | Value |
|---|---|
| Bus stands | 91 |
| Routes / corridors | 273 |
| Timetable services | 602 |
| Departures modelled | 5,494 |
| Offline dataset size | ~439 KB |
| App languages | 4 (en, mr, hi, kn) |
| Voice languages | 3 (mr, hi, en) + code-switching |
| Simulated live fleet | 220 buses |
| Bus classes in fare engine | 8 |
| Concession categories | 6 |

## Tech Stack
Flutter 3.24 · Dart 3.11 · Riverpod · Firebase (Auth, Firestore, RTDB, Storage) · Google Maps · OSRM · Google ADK + Gemini Live · Neural TTS · Python · Node.js.

## What Makes It Different (Top 5)
1. **An empathetic AI "human" officer** on the phone replaces "Press 1" menus.
2. **One offline engine serves app, voice, and SMS**, so every channel gives the same answer.
3. **Time-dependent Dijkstra over stops** with real MSRTC fares and traffic-aware ETAs.
4. **Safety first**: night-halt alerts, arrival alerts, and emergency triage on calls.
5. **Zero placeholder data**: built on official MSRTC Trip Master data and published fare rules.

## Status
- ✅ Mobile app: feature-complete prototype (planner, fares, ETA, map, navigation, alerts, tickets, i18n, themes, accessibility).
- ✅ Voice AI: working desktop simulator with live Gemini audio, tools, CRM, emergency handling, and call recording.
- 🟡 Next: PSTN telephony integration, AIS-140 VLTS feed, conductor dashboard, SMS/USSD.

## Business Model
**B2G**: state transport corporations adopt the platform. The rider app is free, the toll-free IVR is advertised on tickets and at stands, and GPS is provided via the existing AIS-140 VLTDs mandated for all public service vehicles.

## Team / Event
Built for **Smart India Hackathon 2026-27**.
