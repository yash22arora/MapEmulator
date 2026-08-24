# Live Location Tracking Emulator — Design Spec

## Purpose

A learning project to understand how apps like Uber, Rapido, and Swiggy show
smooth, live-updating rider/cab positions on a map client, despite receiving
discrete, potentially irregular location updates from the server. The core
techniques being learned:

1. **Server-Sent Events (SSE)** for pushing location updates from backend to client.
2. **Client-side interpolation** so the on-screen marker glides between
   positions instead of jumping/snapping.
3. **Multi-tenant producer/consumer pub/sub** — multiple riders publishing to
   named topics, multiple customers subscribing to the topic they care
   about, backed by independent per-topic queues on the server.
4. **Client-side offline queueing** — buffering events locally on a flaky
   producer and flushing the backlog once connectivity returns.

A secondary goal is understanding where and why **queues** show up in this
kind of pipeline (producer/consumer decoupling, backpressure, conflation of
stale updates — both server-side per-topic conflation and client-side
offline buffering).

This is explicitly a **learning exercise**, not a production build. The
owner (an iOS developer with some web/backend experience) will write the
majority of the code themselves; the assistant's role is to break work into
digestible phases, provide guidance/hints/boilerplate syntax on request, and
quiz the owner after each phase to confirm understanding before proceeding.

## Non-goals

- No real authentication, database, or persistence — everything is in-memory
  and resets on server restart. Topic names are a routing key, not an auth
  boundary — anyone who knows/guesses a topic name can publish or subscribe
  to it.
- No automated test suite — verification is manual (`curl`, browser dev
  tools, iOS Simulator + console logs) at each phase checkpoint.
- Not optimized for production correctness/scale — optimized for surfacing
  the underlying concepts clearly.
- Rider's offline/low-network local queue is in-memory only, not persisted
  to disk — an app kill while "offline" loses the buffer.
- Topics are created lazily on first use (producer or consumer, whichever
  hits first) and never torn down — matches the project's existing
  reset-on-restart, no-persistence stance.

**Retracted as of 2026-08-14:** "no multiple concurrent riders/clients" is no
longer a non-goal — multi-tenant pub/sub across topics is now a core goal
(see Amendments).

## Architecture

```
Map Emulator/
├── backend/              Node.js + Express + TypeScript
│   ├── public/            Leaflet + OpenStreetMap control UI (static HTML/JS)
│   │                        — kept as a secondary/admin producer, now topic-aware
│   └── src/                Express app: topic-scoped ingestion endpoint,
│                            per-topic in-memory queues, per-topic worker
│                            loops, per-topic SSE broadcast endpoint
└── ios-client/            SwiftUI Xcode project, single app target
    ├── HomeView            Topic name field + "Enter as Rider"/"Enter as
    │                        Customer" navigation
    ├── RiderView           MapKit — tap-to-select point, low-network mode
    │                        toggle + local offline queue
    └── CustomerView        Google Maps SDK (GMSMapView) — SSE subscriber,
                             interpolation, MKDirections-computed route
                             rendered as a GMSPolyline
```

**Runtime topology:** Backend runs locally on the developer's Mac
(`localhost:<port>`). The iOS client runs in the iOS Simulator, which shares
the Mac's network stack, so it talks to the backend directly at
`http://localhost:<port>` — no LAN/IP configuration needed. Google Maps SDK
requires a real device network path to Google's tile/API servers (unlike
MapKit, this isn't bundled offline), and a Maps SDK for iOS API key supplied
by the owner.

## Data flow

Per topic, independently, N topics running concurrently:

```
Rider (iOS, MapKit) — tap to select point
   │
   ▼  (online) POST /location  { topic, lat, lng, ts }
   │  (offline/low-network mode) buffered into a local in-memory array
   │  instead; on toggling back online, the whole backlog is replayed as a
   │  rapid burst of individual POSTs against the same endpoint
   ▼
Backend: topic looked up/created in a Map<topic, TopicChannel> —
each TopicChannel owns its own queue, worker, and connections list
   │
   ▼
enqueue(update) into that topic's queue
   │
   ▼
That topic's worker loop (fires every ~500ms)
   │  dequeues; if multiple updates queued, keeps only the latest
   │  (server-side conflation — same mechanism as before, now scoped per topic)
   ▼
Broadcast via SSE to clients subscribed to that topic only
   │
   ▼
Customer (iOS, Google Maps): GET /location/stream?topic=X, hand-rolled SSE parser
over URLSession.bytes(for:) → parses `data:` lines → new coordinate
   │
   ▼
Client-side interpolation: animate GMSMarker from last known position
to new position, rather than snapping
   │
   ▼
GMSMarker (cab/bike icon) renders smooth movement, rotated to face
direction of travel; route to the fixed drop point computed via
MKDirections and drawn as a GMSPolyline overlay
```

The per-topic queue/worker exists to demonstrate three real-world concerns:
producer/consumer rate mismatch (rapid clicks vs. a rate-limited dispatch
loop), **server-side conflation** (same pattern as Kafka compacted topics or
RxJS `sample()` — only the latest state matters per topic, older queued
updates are safely discarded), and **multi-tenant isolation** (each topic's
queue/worker/connections are independent, so one busy topic can't starve
another's dispatch timing). The Rider's local offline buffer demonstrates a
distinct, complementary concept — **client-side offline queueing** — where
the producer itself, not the backend, is the one absorbing a period of
unreliability.

## Phase breakdown

| # | Phase | What gets built | Core concept |
|---|-------|------------------|---------------|
| 0 | Setup | Folder structure, Express skeleton, Xcode project scaffold | Project scaffolding |
| 1 | SSE fundamentals | Bare `/stream` endpoint pushing a hardcoded, timed sequence of coordinates; verified with `curl` | The SSE wire protocol (`text/event-stream`, `data:` framing, keep-alive) |
| 2 | Naive end-to-end pipe | Leaflet control UI → `POST /location` → **directly** broadcast via SSE (no queue yet) | Wiring a full producer→consumer loop in its simplest form |
| 3 | Queue + rate-limited worker | Refactor Phase 2: `POST` enqueues, a worker loop dequeues/conflates on an interval and broadcasts | Decoupling, backpressure, conflation |
| 4 | iOS client, no interpolation | SwiftUI MapKit view, hand-rolled SSE client, marker snaps directly to each new coordinate | Consuming SSE on iOS; seeing the "jump" problem firsthand |
| 5 | Route rendering | Fixed drop/pickup coordinate; `MKDirections` computes a road-snapped route once from the rider's starting position, rendered as a static `MapPolyline` overlay | Apple's native routing API (`MKDirections`/`MKRoute`); one-shot async request vs. a live stream |
| 6 | App restructure | `HomeView` (topic field + Rider/Customer nav buttons), scaffolded `RiderView`/`CustomerView`, `NavigationStack` wiring, shared topic state passed down two divergent flows | Single-app multi-role navigation |
| 7 | Backend multi-tenancy | `Map<topic, TopicChannel>`, each with its own queue/worker/connections, lazily created on first use; `POST /location` and `GET /location/stream` become topic-scoped; Leaflet control UI gets a topic field | Pub/sub partitioning — independent producer/consumer pipelines sharing one process |
| 8 | Rider client | MapKit tap-to-select point, `POST /location` with topic, wired against Phase 7's backend | Producing into a named topic |
| 9 | Customer client + Google Maps | `GMSMapView` integration (API key setup, `GMSMapView`/`GMSMarker`), SSE subscribe by topic, marker **snaps** (no lerp yet — deliberately re-surfaces the "jump" problem on the new SDK), `MKDirections`-computed route rendered as a `GMSPolyline` | New map SDK's core APIs; separating "compute a route" from "render a route" |
| 10 | Client-side interpolation | Linear interpolation (lerp) between last and new position on the `GMSMarker`, animated over a fixed duration | Core interpolation math + animation loop, now against Google Maps' marker API |
| 11 | Realism upgrade | Animation duration adapts to the real `ts` gap between updates (clamped 0.3-3.0s), replacing Phase 10's fixed duration; per-segment bearing rotation (great-circle formula, corrected for the marker icon's authored orientation) applied to the marker icon. Also completed two parked items: erasing the traveled portion of the route `GMSPolyline` behind the marker (from Phase 10), and dynamic camera framing via `GMSCoordinateBounds`/`GMSCameraUpdate.fit` capped at zoom 17 (from the stretch goals list, pulled forward once this phase's per-segment machinery made it straightforward) | Matching client animation timing to real update cadence; heading/bearing math |
| 12 | Rider offline queueing | Built on the Leaflet control UI rather than `RiderView` (owner's redirect, easier to test without an Xcode rebuild cycle). "Low-Network Mode" checkbox as a manual override, combined with real `fetch`-failure detection as the actual mechanism apps can trust (`navigator.onLine` only reflects network-interface state, not backend reachability). Full backlog flushed as individual `POST /location` calls (not conflated client-side) on checkbox-off, a real `online` event, or any subsequent send succeeding. Closed the parked Phase 8 fix (`DummyQueue` conflates by arrival order, not `ts`; now keeps only the max-`ts` item on `enqueue`) plus a related gap found during this phase's design discussion: `TopicChannel.addConnection` now replays the last known state to newly-joining consumers immediately, instead of leaving them silent until the next real update | Client-side offline queueing, distinct from and complementary to server-side conflation (Phase 7); the gap between network-interface reachability and actual server reachability |
| 13 | Resilience | SSE reconnect/retry logic on the Customer client (exponential backoff, capped at 4 attempts); backend handles per-topic client disconnects gracefully (`'error'` listener on each connection, guarded broadcast writes, `removeConnection` centralizing the stop-when-empty check). Retry loop designed with a seam for Phase 14: a distinguishable "terminal, don't retry" signal the loop already knows to check for and bypass backoff/retry on, even though nothing throws it yet | Real-world connection handling for a long-lived stream, now in a multi-tenant context; distinguishing transient disconnects from deliberate completion |
| 14 | Delivery completion | Mark an order "Done" via a new backend capability; broadcasts a distinct SSE `event: completed` (not a plain `data:` message) to every connected consumer for that topic, instead of relying on connection-closure semantics, which Phase 13's retry loop makes ambiguous (a plain close now means "reconnect," not "finished"). Customer's SSE parser recognizes the `completed` event specifically and finishes the stream with no retry, using the seam left in Phase 13 | Why closure semantics alone can't express "deliberately finished" once reconnection-on-disconnect is the default; explicit application-level signals vs. transport-level ones |

**Stretch goals (post-core, optional):** add an "auto-drive a route" mode to
the Rider UI to stress-test interpolation with frequent regular updates,
replay buffer so a reconnecting Customer (Phase 13) can catch up via the
queue instead of only seeing the live edge, topic list/discovery UI instead
of free-text entry. (Dynamic camera framing, formerly listed here as
parked from Phase 10, was built in Phase 11 instead — see the Phase 11
row above.)

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

None outstanding. Original round: Google Maps vs. MapKit, backend stack,
control UI map, networking, interpolation depth, resilience scope — all
resolved during initial design discussion (see Phase numbers in the table
above, current as of the 2026-08-14 renumbering). 2026-08-14 round: control
UI's fate, which client(s) get Google Maps, swap-vs-lerp ordering, reconnect
flush strategy, and topic architecture — all resolved, see Amendments below.

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
- **2026-07-03, after Phase 4:** Clarified a motive that was implicit but
  undocumented — the rider marker is meant to move toward a **fixed
  drop/pickup point**, with the route from rider to that point highlighted
  on the map (closer to actual ride-hailing UX, not just a marker floating
  with no destination context). Confirmed MapKit supports this natively
  (`MKDirections`/`MKRoute` for a real road-snapped route, no new
  dependency, no billing account — same free/no-key story as MapKit
  itself), so the earlier Google Maps vs. MapKit decision stands unchanged.
  Inserted as a new Phase 5 (route rendering), renumbering the former
  Phases 5-7 to 6-8. The route is computed **once** per rider starting
  position and rendered as a static overlay — it does not recompute as the
  rider moves, and the rider marker does not snap to it (road-snapping the
  live marker itself is out of scope, a possible future stretch goal). **This
  framing is stale as of the actual Phase 5 build:** the owner confirmed
  during implementation that the route should recompute on every rider
  update instead (matching real ride-hailing apps), a deliberate trade-off
  documented in `docs/progress-log.md`'s Phase 5 entry rather than re-edited
  here. That recompute-per-update behavior carries forward into Phase 9's
  Google Maps port.

- **2026-08-14, before Phase 6:** Major scope expansion, owner-initiated.
  Original single-client design retargeted into two roles — **Rider** and
  **Customer** — sharing one iOS app, with a home-screen topic name field
  routing into either flow. The backend gains **topic-based multi-tenancy**
  (independent per-topic queue/worker/connections, matching real
  publish-subscribe systems) so multiple riders and customers can operate
  concurrently on different topics. The Customer client swaps its map
  renderer to the **Google Maps SDK for iOS** (owner-supplied API key);
  the Rider client keeps MapKit. Former Phases 6-8 (interpolation, realism,
  resilience) are renumbered to 10-11 and 13, with new Phases 6-9 and 12
  inserted for the restructure, backend multi-tenancy, Rider client, and
  Customer+Google-Maps client respectively, plus a new Phase 12 for
  Rider-side offline/low-network local queueing. Key decisions made during
  design discussion, each deliberately chosen over a real alternative:
  - The Leaflet browser control UI is **kept**, not retired, as a
    secondary/admin producer — now also topic-aware — rather than folding
    all point-selection exclusively into the Rider iOS client.
  - Only the **Customer** client switches to Google Maps; **Rider** stays on
    MapKit, both to avoid redoing already-working Phase 0-5 code and to
    contrast the two SDKs side by side.
  - The Google Maps swap happens **before** interpolation/realism (Phase 9,
    ahead of Phases 10-11) rather than after, so the lerp/bearing animation
    logic is written once directly against `GMSMarker` instead of being
    built on MapKit and re-ported.
  - Route computation for the Customer client **stays on `MKDirections`**
    (a CoreLocation service, independent of which SDK renders the result)
    with the output drawn as a `GMSPolyline`, rather than switching to
    Google's own Directions API — avoids a second new REST integration and
    Google Cloud billing surface in the same phase as the SDK swap.
  - Topic architecture is **per-topic queue + worker + connections**
    (true tenant isolation, closer to Kafka partitions) rather than one
    shared queue/worker routing by a topic tag on each item — chosen so one
    busy topic's dispatch timing can't affect another's, and so "multiple
    riders simultaneously" is genuinely independent, matching the owner's
    stated goal of learning multi-tenant producer/consumer patterns.
  - Rider's low-network-mode reconnect **flushes the entire local backlog**
    as a burst of individual `POST /location` calls (re-exercising the
    Phase 3 backend conflation path under load) rather than having the
    client itself conflate down to a single latest point before sending.

- **2026-08-15, during Phase 7:** Owner renamed the SSE subscribe endpoint
  from `GET /stream` to `GET /location/stream`, to read consistently
  alongside `POST /location` now that both live under the same resource.
  Applies from this point forward; earlier phase entries in the learning
  and progress logs describing `GET /stream` remain accurate as historical
  record of what existed at the time and were not retroactively edited.
