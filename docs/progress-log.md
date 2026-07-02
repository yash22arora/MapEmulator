# Progress Log

A running, phase-by-phase summary of the actual code changes: what got
built, who wrote it (owner vs. Claude-scaffolded), what good practices
showed up along the way, and what gaps/lessons surfaced. This is distinct
from [docs/learning-log.md](learning-log.md), which is the verbatim
quiz Q&A transcript — this file is about the *code*, that one is about the
*concept checks*. Newest entries at the bottom.

---

## Phase 0 — Setup

**Scaffolded by Claude** (setup/plumbing, not a learning objective per the
design spec): Express skeleton (`backend/`), Xcode SwiftUI project
(`ios-client/`), `.gitignore`s for both.

**Owner decision:** requested Swift 6 language mode with strict
concurrency enforced. `SWIFT_VERSION` bumped 5.0 → 6.0 in
`project.pbxproj` (the actual on/off switch for data-race-safety errors —
the template's pre-existing `SWIFT_STRICT_CONCURRENCY = complete` only
does meaningful work in Swift 5 mode). Verified with a real `xcodebuild`
simulator build, not just "looks right."

**Lesson surfaced:** initial mental model conflated "Swift 6 mode" with
"strict concurrency checking" as two independently-toggleable things —
they're not. See Phase 0 entry in the learning log for the full
correction.

---

## Phase 1 — SSE fundamentals

**Owner-written:** `GET /stream` — correct `text/event-stream` headers,
proper `data: ...\n\n` framing, `setInterval`-driven hardcoded coordinate
push.

**Good practice, unprompted:** added `req.on('close')` cleanup
(`clearInterval` + `res.end()`) without being asked to — good instinct for
resource cleanup on an open-ended connection, before "connection
lifecycle" was even the explicit topic.

**Gap identified and closed:** didn't know why `Connection: keep-alive`
was in the boilerplate headers. Turned out to be a legacy HTTP/1.0
holdover with no effect on a modern HTTP/1.1 Node server (meaningless over
HTTP/2 entirely). Correctly reasoned through the actual blank-line framing
mechanic (`\n\n` signals event-complete) with only minor imprecision.

---

## Phase 2 — Naive end-to-end pipe

**Owner-written:** `connections: Response[]` registry in `/stream`,
`POST /location` broadcasting to all registered connections, Leaflet
control UI wired to `POST` on map click (HTML/JS boilerplate for the
Leaflet part was handed over directly, since it's tooling, not a learning
target).

**Real debugging encountered:** hit a genuinely confusing bug — a stale
`node` process from an earlier run was still bound to port 3000 and
answering requests with old code, making `GET /` 404 even though the
current `index.html` was correct on disk. Root-caused via `lsof -i :3000`
rather than guessing. Led directly to adding `nodemon` (later replaced by
`tsx watch` in Phase 3) for auto-restart, closing off this whole class of
bug going forward.

**Design gap named, deliberately deferred:** the control UI is
producer-only (no `EventSource` back to `/stream`), so multiple open tabs
don't sync with each other — correctly diagnosed when asked. Also
identified: an ungracefully-dropped `/stream` connection leaves a stale
`res` in `connections`, and writing to it later risks an unhandled
`'error'` event **crashing the whole Node process** — explicitly filed for
Phase 7 (resilience) rather than patched ad hoc.

---

## Phase 3 — Queue + rate-limited worker (conflation)

**Mid-phase architecture change, owner-requested:** converted the entire
backend from plain JS to TypeScript (`tsconfig.json`, `@types/express`,
`@types/node`; `nodemon` → `tsx watch` for dev, `tsc` → `dist/` for a real
build). Mechanical/tooling work, done by Claude; verified across all three
run modes (typecheck, dev watch, build+run) with actual `curl` requests,
not just "it compiled."

**Owner-written:** `DummyQueue<T>` (generic, capacity-capped with
oldest-item eviction), `services.ts`'s `broadcastWorker` (drain-and-
conflate-and-broadcast on a fixed interval), refactored `POST /location`
to enqueue instead of broadcasting directly. Good module boundaries:
queue mechanics, broadcast logic, and shared types cleanly split into
`queue.ts` / `services.ts` / `types.d.ts` rather than piling into
`server.ts`.

**Bugs found during verification, both owner-fixed:**
1. *Log spam on idle ticks* — `console.log` and `queue.empty()` ran
   unconditionally every worker tick, logging nonsense (`Dropped: -1`,
   `Broadcasted: undefined`) even when nothing had happened. Fixed by
   moving both inside the `if (recentLocation)` guard.
2. *A real strongly-typed-data gotcha* — `types.d.ts` declared `ts: Date`,
   but the control UI actually sends `Date.now()` (a `number`) through
   `JSON.stringify`. TypeScript compiled cleanly regardless, because
   `Request<{}, {}, LocationUpdate>` is a compile-time assertion about
   `req.body`, not a runtime check — and TS types are erased entirely by
   the time compiled code executes, so there's nothing left at runtime to
   validate against anyway. Fixed by aligning the type to `ts: number`,
   the actual shape of the data. Correctly reasoned through *why* on
   request — see Phase 3 entry in the learning log.

**Verified behavior:** burst-tested with 5 rapid `POST`s inside one
worker tick via `curl`; confirmed exactly 1 of 5 updates (the latest)
reached the SSE stream, with an accurate `Dropped: 4` log line and no
spam on subsequent idle ticks.

**Running theme across Phases 1-3:** a consistent, healthy instinct to
add resource-cleanup / defensive code beyond what was strictly asked
(disconnect handling, queue capacity caps) — balanced against a couple of
"the type system says X but reality is Y" gaps that are exactly the kind
of thing static typing *feels* like it should catch but doesn't, without
runtime boundary validation. Worth watching whether this pattern
(trusting an asserted type over verifying the actual runtime shape)
recurs once the iOS/Swift side starts parsing untyped SSE payloads in
Phase 4.
