# 🚌 BussPass: AI Human Operator IVR System Architecture
## Software-Only Conversational AI for MSRTC State Transport

> **SIH 2026 Innovation**: Replacing rigid, robotic touch-tone IVRs with a warm, empathetic, context-aware **AI Human Enquiry Officer** ("Aapli ST Helpdesk Officer") operating 100% in software. It is built on the **Google Agent Development Kit (ADK)** with **Gemini Live** native streaming audio, and uses tool-calling into real-time MSRTC Timetable/Firestore data and live bus positions from the buses' **existing AIS-140 VLTS** (no custom tracking hardware).

---

```
                                  AI HUMAN IVR ARCHITECTURE
                                  
  ┌─────────────────┐       ┌─────────────────────────────────┐       ┌────────────────────────┐
  │   USER INPUT    │       │     SOFTWARE TELEPHONY GATEWAY  │       │  CONTEXT & STATE MGR   │
  │ (Phone / WebRTC │ ───►  │  (WebSocket / SIP Stream / GUI) │ ───►  │ (Language, Session ID, │
  │   / Desktop)    │       └─────────────────────────────────┘       │   Active Phone Ticket) │
  └─────────────────┘                        │                        └───────────┬────────────┘
                                             ▼                                    │
                            ┌─────────────────────────────────┐                   │
                            │  GOOGLE ADK RUNNER (run_live)   │ ◄─────────────────┘
                            │  + GEMINI LIVE (native audio)   │
                            │  (Empathetic Officer Persona)   │
                            └─────────────────────────────────┘
                                             │
                                   ADK Tool Calling
                                             │
                ┌────────────────────────────┼────────────────────────────┐
                ▼                            ▼                            ▼
   ┌─────────────────────────┐  ┌─────────────────────────┐  ┌─────────────────────────┐
   │ MSRTC TIMETABLE ENGINE  │  │ LIVE BUS TRACKING       │  │ PASSENGER TICKET LOOKUP │
   │  (Top 3 Upcoming Buses  │  │ (Existing AIS-140 VLTS  │  │   (Auto-fetched via     │
   │   near current time)    │  │  feed → RTDB: speed/ETA)│  │    Caller ID on Ring)   │
   └─────────────────────────┘  └─────────────────────────┘  └─────────────────────────┘
                │                            │                            │
                └────────────────────────────┼────────────────────────────┘
                                             ▼
                            ┌─────────────────────────────────┐
                            │    HUMAN CONVERSATIONAL OUTPUT  │
                            │  1. Intent Acknowledgment       │
                            │  2. Top 3 Bus Departures        │
                            │  3. Boarding Platform & Bay     │
                            │  4. Deboarding Central Stand    │
                            └─────────────────────────────────┘
                                             │
                                             ▼
                            ┌─────────────────────────────────┐
                            │   GEMINI LIVE NATIVE AUDIO OUT  │
                            │  (Marathi / Hindi / English)    │
                            └─────────────────────────────────┘
```

### Live tracking source
Live bus positions are **not** produced by any BussPass hardware. State transport buses already carry **AIS-140 Vehicle Location Tracking Devices** (MoRTH mandate) reporting to the STC's VLTS. The BussPass **VLTS Integration Adapter** ingests that feed into Firebase RTDB `buses/{busId}`, which the `get_live_bus_eta` tool reads.

### Google ADK building blocks
| ADK component | Role in BussPass |
|---|---|
| `google.adk.Agent` | Officer persona (instruction) + list of Python tools |
| `Runner` + `run_live()` | Bidirectional streaming session per call |
| `LiveRequestQueue` | Pushes 16 kHz PCM caller audio blobs into the session |
| `InMemorySessionService` | Per-call session state (prototype; swap for persistent store in prod) |
| Tool functions | `get_top3_upcoming_buses`, `get_route_details`, `get_fare_details`, `get_live_bus_eta`, `get_caller_ticket`, `get_caller_profile`, `update_caller_profile`, `handle_emergency` |

---

## 1. The 4 Core Principles of the "AI Human" System

### 1. Zero Generic / Canned Responses
* **Old IVR**: "Press 1 for timetable. Invalid option. Goodbye."
* **BussPass AI Human**: "नमस्कार! मला समजले, तुम्ही संगमनेरहून नाशिकला जाणाऱ्या बसबद्दल विचारत आहात. मी लगेच वेळापत्रक तपासून सांगतो..."

### 2. Context-Aware Active Listening
* As soon as the call connects, the system pre-fetches the caller's active ticket from Firestore using their **Caller ID**. The AI knows *who* is calling, *what bus* they booked, and *where* they are going before they even speak.

### 3. Real-Time Timetable Calculation (Top 3 Nearest Departures)
* Instead of reading out 50 bus timings, the system checks the **current local clock time** and computes the **top 3 closest upcoming bus departures** (e.g. 6:00 AM Lalpari, 7:30 AM Shivshahi, 9:00 AM Ordinary) along with exact **Boarding Platform/Bay** and **Deboarding Stand**.

### 4. Code-Switching & Dialect Resilience
* Elderly passengers in Maharashtra speak mixed Marathi/Hindi ("संगमनेर से नाशिक बस वेळ काय आहे?"). The AI detects intent naturally regardless of grammar, accents, or spoken numbers (e.g. "बारा चौतीस" = 1234).

---

## 2. Dynamic Tool Definitions (Google ADK Tool Calling)

The AI Operator's core tools (ADK derives these schemas automatically from the Python function signatures and docstrings). Representative schemas:

```json
[
  {
    "name": "get_top3_upcoming_buses",
    "description": "Computes the top 3 nearest upcoming bus departures from current clock time for any MSRTC route.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "origin_city": { "type": "STRING", "description": "Origin bus stand e.g. Sangamner, Swargate, Pune" },
        "destination_city": { "type": "STRING", "description": "Destination bus stand e.g. Nashik, Lonavala, Mumbai" }
      },
      "required": ["destination_city"]
    }
  },
  {
    "name": "track_live_bus_gps",
    "description": "Fetches live location, current speed, next stop, and ETA for a bus number from the existing AIS-140 VLTS feed (via RTDB).",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "bus_number": { "type": "STRING", "description": "Bus registration number e.g. MH-12-AB-1234" }
      },
      "required": ["bus_number"]
    }
  },
  {
    "name": "lookup_caller_ticket",
    "description": "Auto-fetches confirmed ticket details linked to caller phone number.",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "phone_number": { "type": "STRING", "description": "10-digit caller phone number" }
      },
      "required": ["phone_number"]
    }
  }
]
```

---

## 3. Human Persona Prompting (System Instruction)

```text
You are Sunita Madam, a senior, warm, empathetic Enquiry Officer at the Maharashtra State Road Transport Corporation (MSRTC) Central Helpdesk.

CONVERSATIONAL RULES:
1. ALWAYS acknowledge the caller's specific intent FIRST before answering.
   - Example (Marathi): "नमस्कार! मला समजले, तुम्हाला संगमनेर ते नाशिक प्रवासाबद्दल माहिती हवी आहे."
   - Example (Hindi): "नमस्कार! मैंने समझा, आप संगमनेर से नासिक जाने वाली बस का समय जानना चाहते हैं।"
   - Example (English): "Hello! I understand you are inquiring about buses from Sangamner to Nashik."

2. ALWAYS provide complete, actionable journey guidance:
   - Exact Boarding Stand and Platform/Bay Number.
   - Top 3 nearest upcoming bus departure times relative to the current time.
   - Bus Type (Lalpari / Shivshahi / Sleeper) and Fare.
   - Exact Deboarding Central Stand.

3. Speak in a natural, friendly, human tone. Never use bullet points, robotic phrases, or technical jargon. Speak as if talking to an elderly family member who needs gentle assistance.
```

---

## 4. Software Deployment Options (No Hardware Required)

All options run the same **Google ADK** agent. Only the audio front-end changes.

1. **Cloud Server (Docker / Cloud Run running the ADK Runner)**:
   * Exposes WebSockets for WebRTC browser apps and mobile audio streams.
2. **SIP / VoIP Gateway (Exotel / Twilio / Asterisk Cloud)**:
   * The media stream from telephone calls is bridged over WebSocket into the ADK `run_live` session.
3. **Local Desktop App (`ivr_simulator_gui.py`, Tkinter)**:
   * Standalone simulator with live microphone, speakers, visual dialpad, call recordings, and a Firestore IoT trigger (`ivr_gateway/current_call`).
4. **Headless (`adk_live_voice.py`)**:
   * Minimal mic ↔ Gemini Live loop for testing.
