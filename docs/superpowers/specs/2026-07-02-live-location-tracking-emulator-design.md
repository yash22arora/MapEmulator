# Live Location Tracking Emulator — Design Spec

## Purpose

A learning project to understand how apps like Uber, Rapido, and Swiggy show
smooth, live-updating rider/cab positions on a map client, despite receiving
discrete, potentially irregular location updates from the server. The two
core techniques being learned:

1. **Server-Sent Events (SSE)** for pushing location updates from backend to client.
2. **Client-side interpolation** so the on-screen marker glides between
   positions instead of jumping/snapping.

A secondary goal is understanding where and why **queues** show up in this
kind of pipeline (producer/consumer decoupling, backpressure, conflation of
stale updates).

This is explicitly a **learning exercise**, not a production build. The
owner (an iOS developer with some web/backend experience) will write the
majority of the code themselves; the assistant's role is to break work into
digestible phases, provide guidance/hints/boilerplate syntax on request, and
quiz the owner after each phase to confirm understanding before proceeding.

## Non-goals

- No real authentication, database, or persistence — everything is in-memory
  and resets on server restart.
- No multiple concurrent riders/clients in the core build (may be a stretch
  goal).
- No automated test suite — verification is manual (`curl`, browser dev
  tools, iOS Simulator + console logs) at each phase checkpoint.
- Not optimized for production correctness/scale — optimized for surfacing
  the underlying concepts clearly.

## Architecture

```
Map Emulator/
├── backend/              Node.js + Express + TypeScript
│   ├── public/            Leaflet + OpenStreetMap control UI (static HTML/JS)
│   └── src/                Express app: ingestion endpoint, in-memory queue,
│                            worker loop, SSE broadcast endpoint
└── ios-client/            SwiftUI + MapKit Xcode project
```

**Runtime topology:** Backend runs locally on the developer's Mac
(`localhost:<port>`). The iOS client runs in the iOS Simulator, which shares
the Mac's network stack, so it talks to the backend directly at
`http://localhost:<port>` — no LAN/IP configuration needed.

## Data flow

```
Control UI (browser, Leaflet map)
   │  click on map
   ▼
POST /location  { lat, lng, ts }
   │
   ▼
enqueue(update)                    [in-memory queue]
   │
   ▼
Worker loop (fires every ~500ms)
   │  dequeues; if multiple updates queued, keeps only the latest
   │  (conflation — stale intermediate positions are discarded)
   ▼
Broadcast via SSE to all connected clients
   │
   ▼
iOS client: SSE stream reader (hand-rolled parser over
URLSession.bytes(for:)) → parses `data:` lines → new coordinate
   │
   ▼
Client-side interpolation: animate marker from last known position
to new position, rather than snapping
   │
   ▼
MapKit annotation (cab/bike PNG) renders smooth movement,
eventually rotated to face direction of travel
```

The queue exists specifically to demonstrate two real-world concerns:
producer/consumer rate mismatch (rapid clicks vs. a rate-limited dispatch
loop) and **conflation** — the same pattern used in systems like Kafka
compacted topics or RxJS `sample()`, where only the latest state matters for
a given key (here, "current rider position") and older queued updates are
safely discarded once a newer one arrives.

## Phase breakdown

| # | Phase | What gets built | Core concept |
|---|-------|------------------|---------------|
| 0 | Setup | Folder structure, Express skeleton, Xcode project scaffold | Project scaffolding |
| 1 | SSE fundamentals | Bare `/stream` endpoint pushing a hardcoded, timed sequence of coordinates; verified with `curl` | The SSE wire protocol (`text/event-stream`, `data:` framing, keep-alive) |
| 2 | Naive end-to-end pipe | Leaflet control UI → `POST /location` → **directly** broadcast via SSE (no queue yet) | Wiring a full producer→consumer loop in its simplest form |
| 3 | Queue + rate-limited worker | Refactor Phase 2: `POST` enqueues, a worker loop dequeues/conflates on an interval and broadcasts | Decoupling, backpressure, conflation |
| 4 | iOS client, no interpolation | SwiftUI MapKit view, hand-rolled SSE client, marker snaps directly to each new coordinate | Consuming SSE on iOS; seeing the "jump" problem firsthand |
| 5 | Client-side interpolation | Linear interpolation (lerp) between last and new position, animated over a fixed duration | Core interpolation math + animation loop (e.g. `CADisplayLink`/`Timer`) |
| 6 | Realism upgrade | Animation duration adapts to the actual gap between updates (not fixed); bearing calculated and applied to rotate the marker PNG | Matching client animation timing to real update cadence; heading/bearing math |
| 7 | Resilience | SSE reconnect/retry logic on the client; server handles client disconnects gracefully | Real-world connection handling for a long-lived stream |

**Stretch goals (post-core, optional):** swap in Google Maps iOS SDK,
support multiple simulated riders, add an "auto-drive a route" mode to the
control UI to stress-test interpolation with frequent regular updates,
replay buffer so a reconnecting client (Phase 7) can catch up via the queue
instead of only seeing the live edge.

## Working process per phase

- The assistant explains the concept and the shape of the phase, then the
  owner writes the implementation.
- The assistant provides hints, and boilerplate/setup syntax on request
  (e.g. SPM/CocoaPods setup, Express routing syntax) rather than full
  solutions.
- At the end of each phase, the assistant asks the owner questions to check
  understanding before moving to the next phase.
- Verification is manual and hands-on: `curl` against SSE endpoints,
  browser dev tools/network tab for the control UI, iOS Simulator + console
  logs for the client.

## Open questions / deferred decisions

None outstanding — Google Maps vs. MapKit (MapKit, no billing setup),
backend stack (Node/Express), control UI map (Leaflet/OSM), networking
(Simulator + localhost), interpolation depth (basic first, realism as
Phase 6), and resilience scope (Phase 7, included) were all resolved during
design discussion.

## Amendments

- **2026-07-02, during Phase 3:** Backend switched from plain JS to
  **TypeScript** (owner requested strongly-typed data for the queue/SSE
  payloads). `nodemon` (added just before this) was replaced by `tsx
  watch`, which handles TS compilation and file-watching in one tool.
  Build/run is now `npm run build` (`tsc`) + `npm start`, or `npm run dev`
  for a watch-mode dev server. The control UI (`backend/public/*`) stays
  plain JS/HTML — it's browser-loaded via `<script>` tag with no bundler,
  so TS there would need a separate build step for no real benefit at this
  project's scale.
