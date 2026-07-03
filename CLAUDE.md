# Map Emulator — Project Instructions

## What this is

A learning project for understanding how apps like Uber/Rapido/Swiggy show
smooth live rider/cab movement on a map: **Server-Sent Events (SSE)** from
backend to client, plus **client-side interpolation** so the marker glides
instead of jumping. A Node backend also has a small in-memory **queue**
(with conflation) between ingestion and broadcast, to demonstrate
producer/consumer decoupling and backpressure — the kind of pattern real
location-tracking backends use.

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
  tiles (no API key, no billing account).
- **iOS client:** SwiftUI + Apple **MapKit** (not Google Maps — avoids
  Google Cloud billing account requirement; concepts transfer 1:1 if he
  wants to swap SDKs later as a stretch goal).
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
Leaflet control UI --POST /location--> enqueue --> worker loop (~500ms,
conflates to latest) --> SSE broadcast --> iOS hand-rolled SSE client -->
client-side interpolation --> MapKit annotation (cab/bike PNG)
```

Single rider, single client, no auth, no DB — everything resets on server
restart.

## Phase progress tracker

Keep this section updated as phases complete, so a fresh session with lost
context can tell where things stand at a glance.

- [x] Phase 0 — Setup (folder structure, Express skeleton, Xcode scaffold)
- [x] Phase 1 — SSE fundamentals (hardcoded `/stream`, verified via `curl`)
- [x] Phase 2 — Naive end-to-end pipe (control UI → POST → direct SSE broadcast)
- [x] Phase 3 — Queue + rate-limited worker (conflation)
- [x] Phase 4 — iOS client, no interpolation (see the "jump" problem)
- [x] Phase 5 — Route rendering (fixed drop point, `MKDirections` road-snapped
      polyline) — inserted 2026-07-03, see Amendments in the design spec.
      Note: route recomputes on every rider update (owner's deliberate
      choice, matching real ride-hailing apps), not once as originally
      speced.
- [ ] Phase 6 — Client-side interpolation (lerp, fixed duration)
- [ ] Phase 7 — Realism upgrade (adaptive duration + bearing rotation)
- [ ] Phase 8 — Resilience (SSE reconnect/retry)

Stretch goals (not started until core phases are done): Google Maps SDK
swap-in, multiple riders, auto-drive-a-route mode, replay buffer on
reconnect.
