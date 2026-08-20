# Map Emulator — Project Instructions

## What this is

A learning project for understanding how apps like Uber/Rapido/Swiggy show
smooth live rider/cab movement on a map: **Server-Sent Events (SSE)** from
backend to client, plus **client-side interpolation** so the marker glides
instead of jumping. A Node backend also has small in-memory **queues**
(with conflation), one per pub/sub **topic**, between ingestion and
broadcast, to demonstrate producer/consumer decoupling, backpressure, and
multi-tenant isolation — the kind of pattern real location-tracking
backends use. A single iOS app hosts two roles — **Rider** (produces
location updates, MapKit) and **Customer** (consumes them, Google Maps SDK)
— selected from a home screen alongside a topic name, so multiple
riders/customers can operate concurrently on independent topics. The Rider
side also simulates offline/low-connectivity conditions with a local queue
that flushes on reconnect.

Full design/rationale lives in
[docs/superpowers/specs/2026-07-02-live-location-tracking-emulator-design.md](docs/superpowers/specs/2026-07-02-live-location-tracking-emulator-design.md).
Read that file for the complete architecture and phase table — this file is
just the quick-reference so a session doesn't have to re-derive it.

Every phase-end concept quiz (question, raw answer, corrections) is logged
in [docs/learning-log.md](docs/learning-log.md) — check it for what's
already been covered and where the owner's understanding has needed
correcting before.

A phase-by-phase summary of the actual code changes (what was built, who
wrote it, good practices demonstrated, bugs found and how they were fixed)
is kept in [docs/progress-log.md](docs/progress-log.md) — update it after
each phase completes, alongside the learning log.

## Who's doing what (read this before writing any code)

This is a **teaching engagement, not a build-it-for-them task**.

- The owner (iOS dev, some web/backend experience) writes the
  implementation themselves.
- Claude's job: explain the concept for the current phase, provide hints
  and boilerplate/setup syntax **on request** (e.g. exact SPM incantation,
  Express route syntax) — not full working solutions.
- Do not jump ahead and implement a later phase's code "to save time."
- At the end of each phase, quiz the owner on the concept before moving to
  the next phase. Don't skip this step even if the owner seems eager to move
  on.
- Log every quiz round in
  [docs/learning-log.md](docs/learning-log.md): the exact question asked,
  the owner's raw answer verbatim (don't paraphrase/clean it up), and
  Claude's assessment/corrections/additions. Update it immediately after
  each quiz, before moving to the next phase — this is what lets a
  context-lost session see not just *what* was covered but *what the owner
  actually understood at the time* and what needed correcting.
- Also update [docs/progress-log.md](docs/progress-log.md) once a phase's
  code is done: a summary of what was built, who wrote it (owner vs.
  Claude-scaffolded boilerplate), good practices worth naming, and any
  bugs found + how they were fixed. This is the code-side counterpart to
  the learning log's concept-side record.
- No automated test suite by design — verification is manual: `curl` /
  browser dev tools for the backend, iOS Simulator + console logs for the
  client.

## Tech stack (locked in during design — don't re-litigate)

- **Backend:** Node.js + Express + **TypeScript** (switched from plain JS
  during Phase 3 — see Amendments in the design spec), in-memory state
  only. Dev: `npm run dev` (`tsx watch`). Build: `npm run build` (`tsc` →
  `dist/`) then `npm start`.
- **Control UI:** static HTML/JS served by Express, Leaflet + OpenStreetMap
  tiles (no API key, no billing account). Kept alongside the Rider iOS
  client as a secondary/admin producer (2026-08-14 decision) — now
  topic-aware too.
- **iOS client:** single SwiftUI app, two roles. **Rider** uses Apple
  **MapKit** (unchanged from Phases 0-5). **Customer** uses the **Google
  Maps SDK for iOS** (owner-supplied API key) — switched 2026-08-14, see
  Amendments in the design spec for why only Customer swaps and Rider
  doesn't. Route computation for Customer stays on `MKDirections`
  (CoreLocation service, SDK-independent) with the result drawn as a
  `GMSPolyline`.
- **Swift language mode:** Swift 6, strict concurrency enforced
  (`SWIFT_VERSION = 6.0` in project.pbxproj). Expect data-race safety
  checks as compiler errors, not warnings — this matters once we write the
  async SSE stream reader in Phase 4 (`URLSession.bytes(for:)` consumption
  will need proper actor isolation / `Sendable` conformance).
- **SSE on iOS:** hand-rolled parser over `URLSession.bytes(for:)` — no
  third-party SSE library. The whole point is understanding the wire
  protocol.
- **Networking:** iOS Simulator + `http://localhost:<port>` — no LAN IP
  config needed since Simulator shares the Mac's network stack.

## Architecture at a glance

```
Rider (iOS, MapKit) --POST /location {topic,...}--> per-topic enqueue -->
per-topic worker loop (~500ms, conflates to latest) --> per-topic SSE
broadcast --> Customer (iOS, Google Maps) hand-rolled SSE client -->
client-side interpolation --> GMSMarker (cab/bike icon), MKDirections
route drawn as GMSPolyline
```

Leaflet control UI remains a secondary/admin producer into the same
topic-scoped `POST /location`. No auth (topic name is a routing key, not a
credential), no DB — everything resets on server restart.

## Phase progress tracker

Keep this section updated as phases complete, so a fresh session with lost
context can tell where things stand at a glance. Renumbered 2026-08-14 —
see Amendments in the design spec for the full rationale behind the scope
expansion and each new phase's ordering.

- [x] Phase 0 — Setup (folder structure, Express skeleton, Xcode scaffold)
- [x] Phase 1 — SSE fundamentals (hardcoded `/stream`, verified via `curl`)
- [x] Phase 2 — Naive end-to-end pipe (control UI → POST → direct SSE broadcast)
- [x] Phase 3 — Queue + rate-limited worker (conflation)
- [x] Phase 4 — iOS client, no interpolation (see the "jump" problem)
- [x] Phase 5 — Route rendering (fixed drop point, `MKDirections` road-snapped
      polyline) — inserted 2026-07-03, see Amendments in the design spec.
      Note: route recomputes on rider update, not once as originally speced
      (owner's deliberate choice, matching real ride-hailing apps) — refined
      2026-08-19 during Phase 10 to only recompute once the rider drifts
      >20m off the existing route (`MKPolyline.distance(to:)`,
      `MKPolyline+Snapping.swift`), not on every single update; see the
      Phase 10 entry in progress-log.md once logged.
- [x] Phase 6 — App restructure (`HomeView` topic field + Rider/Customer nav,
      scaffolded `RiderView`/`CustomerView`)
- [x] Phase 7 — Backend multi-tenancy (per-topic queue/worker/connections;
      `POST /location` and `GET /location/stream` become topic-scoped;
      endpoint renamed from `/stream` mid-phase for consistency with `POST
      /location`)
- [x] Phase 8 — Rider client (MapKit tap-to-select point, posts to topic)
- [x] Phase 9 — Customer client + Google Maps SDK swap (marker snaps, no
      lerp yet; `MKDirections` route rendered as `GMSPolyline`)
- [x] Phase 10 — Client-side interpolation — redirected from hand-rolled
      lerp/Timer math (owner's call) to `CATransaction`-driven route-snapped
      interpolation on `GMSMarker`: raw GPS pings snap onto the route
      polyline and the marker animates through the actual road-following
      sub-path between them (U-turns included), not a straight line. See
      the Phase 10 entry in progress-log.md for the full design.
- [ ] Phase 11 — Realism upgrade (adaptive duration + bearing rotation).
      Parked here from Phase 10: erase the traveled portion of the route
      `GMSPolyline` behind the marker as it animates, instead of the
      polyline staying static — ties to this phase's per-segment animation
      progress tracking, which bearing calculation also needs.
- [ ] Phase 12 — Rider offline queueing (low-network toggle, local buffer,
      full-backlog burst-flush on reconnect). Parked here from Phase 8:
      `DummyQueue.getRecentItem()` conflates by arrival order, not by
      `ts` — a burst-flush could deliver an older-`ts` update after a
      newer one and let the older one win. Fix is an `O(1)` running
      max-by-`ts` comparison on `enqueue`, not a full priority queue
      (nothing needs ranked access beyond "the single freshest item,"
      since the queue is fully drained every broadcast tick anyway). See
      the Phase 8 entry in learning-log.md for the full reasoning.
- [ ] Phase 13 — Resilience (Customer SSE reconnect/retry, backend
      per-topic disconnect handling)

Stretch goals (not started until core phases are done): auto-drive-a-route
mode, replay buffer on reconnect, topic list/discovery UI. Parked from
Phase 10: dynamic camera framing — fit zoom/pan to a padded bounding box
around the home marker, rider marker, and route polyline instead of a
fixed zoom level.
