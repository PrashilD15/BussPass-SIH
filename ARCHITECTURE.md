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

2. **`routes`** (Planned):
   - Defines bus lines (e.g., MSRTC-PUN-MUM-AC).
   - Contains metadata (bus type, total distance).

3. **`route_stops`** (Planned):
   - The graph structure mapping stops to routes with sequence orders and estimated arrival times.

### Journey Planner & Distributed Memoization (Cache)
Calculating complex routes with transfers (A* or Dijkstra's) is heavy. We use a **Distributed Memoization** pattern:
- **Client-Side Calculation**: The first time a specific Origin-Destination pair is searched, the Flutter app downloads the graph, calculates the fastest route, and displays it.
- **`route_cache` Collection**: The calculated result is immediately saved back to Firestore in `route_cache`.
- **Cache Hits**: Any subsequent user searching the exact same Origin-Destination pair will bypass the calculation and instantly read the pre-computed route from `route_cache`, scaling infinitely with minimal compute costs.

## 4. Map Integrations
- Uses `google_maps_flutter`.
- Nearest bus stops are loaded natively into the map.
- Uses custom drawn `BitmapDescriptor` canvases (Premium Slate circles with bus icons) to highlight bus stands dynamically without needing external image assets.
