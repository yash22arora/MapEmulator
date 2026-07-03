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

---

## Phase 4 — iOS client, no interpolation

**Owner-written, good structure from the start:** clean MVVM-ish layout —
`Models/LocationUpdate.swift`, `DataManagers/LiveViewDataManager.swift`
(protocol + implementation, `LiveViewDataManaging`), `ViewModels/
LiveViewViewModel.swift` (`@Observable`), `Views/LiveView.swift`. Good
instinct to protocol-ize the data manager for testability/DI even though
nothing's actually testing it yet.

**Design flaw caught before it shipped:** first draft of
`LiveViewDataManaging.startStreaming()` returned `async throws ->
LocationUpdate` — a single value — which can't represent a live,
indefinite stream of updates. Claude explained `AsyncThrowingStream`
(continuation-based bridge from a push-style producer to something
consumers can `for try await` over); owner correctly reasoned through
*why* it's necessary on request (see learning log) rather than just
pattern-matching the fix.

**Bugs found and fixed, roughly in the order hit:**
1. *Compile error* — `for try await update in dataManager.startStreaming()`
   where `startStreaming()` was itself `async throws`, needing its own
   `try await` separate from the loop's. Resolved by removing `async
   throws` from the signature entirely (the function doesn't actually do
   anything async/throwing before returning the stream — all real work
   happens inside the stream's own `Task`), which was the more correct fix
   than just adding a second `try await` at the call site.
2. *Wrong endpoint* — `/streaming` instead of `/stream`, a typo that would
   have silently 404'd and ended the stream immediately via the status
   code guard.
3. *SSE parsing bug, most significant one this phase* — the loop attempted
   to `JSONDecoder().decode(...)` on **every** line from `bytes.lines`,
   including the blank line that terminates each SSE event (our server
   sends `data: {...}\n\n`, and `.lines` splits that into two lines: the
   data line and an empty one). Decoding empty `Data` throws, uncaught,
   which terminated the entire `AsyncThrowingStream` after exactly one
   successful update — a bug that would look like "it worked once then
   silently died," not an obvious crash. Went through two intermediate
   attempts before landing on the right fix:
   - First attempt: `line.replacingOccurrences(of: "data: ", with: "")` —
     works by coincidence for numeric JSON payloads, but is a global
     find-replace, not a prefix strip (wrong tool, latent corruption risk
     if a payload ever contained that substring).
   - Second attempt: `if let payload = line.trimmingPrefix("data: ")` —
     `trimmingPrefix` returns a non-optional `Substring` (unchanged
     string if no match, never `nil`), so this doesn't compile, and even
     if it did, wouldn't have distinguished "had the prefix" from "didn't."
   - Final, correct fix: `if line.hasPrefix("data: ")` as the gate,
     `line.trimmingPrefix("data: ")` only inside it to do the actual
     stripping — separating the boolean check from the transformation.
4. *Backend bug surfaced by iOS testing, not iOS-side at all* —
   `connections = connections.filter(...)` on client disconnect reassigns
   the module-level array to a new object; the broadcast worker had
   captured a reference to the original array at startup and never saw
   the reassignment, so broadcasts silently stopped reaching any client
   that connected after the *first* disconnect ever occurred. Classic
   mutate-vs-reassign reference bug. Fixed with `connections.splice(
   connections.indexOf(res), 1)` (in-place mutation, same object
   reference preserved). One residual edge case flagged, not yet
   hardened: `indexOf` returning `-1` would make `splice(-1, 1)` delete
   the *last* element instead of no-op'ing — low probability (`close`
   shouldn't fire twice for one response) but not impossible.

**Verified:** clicking the control UI map is reflected in the iOS
Simulator/Preview, and — the actual point of this phase — the marker
**snaps/teleports** rather than gliding, confirmed directly by the owner.
Phase 5 (originally interpolation, renumbered to Phase 6 — see below)
exists to fix exactly that.

**Scope change, end of this phase:** owner clarified the emulator's real
goal includes a rider moving toward a **fixed drop point**, with the
route highlighted — not just a marker floating with no destination
context. Confirmed MapKit's `MKDirections`/`MKRoute` covers this natively
(free, no billing account, same as MapKit itself), so no library switch
needed. Inserted as a new Phase 5 (route rendering); former Phases 5-7
renumbered to 6-8. See Amendments in the design spec.

---

## Phase 5 — Route rendering (MKDirections)

**Owner-written:** `LiveViewViewModel.requestMapRoute()` (`MKDirections.Request`
→ `MKDirections(request:).calculate()` → `route.polyline`), `HomeView.swift`
(new landing screen with `NavigationPath`-based navigation into `LiveView`),
map styling (`pointsOfInterest: .excludingAll`) and a "Home" `Annotation`.
`riderLocation` changed from `LocationUpdate?` to `CLLocation?` (a real
CoreLocation type instead of the raw network model, more natural fit for
feeding directly into `MKMapItem`).

**Design decision, explicitly confirmed rather than assumed:** the route
recomputes on **every** rider location update (via `.onChange`), not once
per starting position as originally speced — owner confirmed this is
intentional, matching real ride-hailing apps (Uber recomputes the
remaining route as the driver moves). Design spec's "computed once, static
overlay" framing is now stale for this specific behavior; noting here
rather than re-editing the spec since the *reason* for the original
design (avoid needless MKDirections calls) was explicitly traded off on
purpose.

**Bugs found and fixed:**
1. *Cascading compiler error* — `if let location = viewModel.riderLocation`
   inside the `Map { }` content builder, after `riderLocation`'s type had
   changed to non-optional `CLLocation` at one point during iteration.
   `if let` on a non-optional is itself invalid, and the failure inside
   the builder closure surfaced as a confusing top-level "no exact matches
   in call to initializer" against `Map` itself, several layers up from
   the actual problem. Root-caused via `xcodebuild`, not guessed.
2. *Race condition on concurrent route requests* — every `.onChange` fired
   an untracked `Task`, so a slow request for an older rider position
   could complete *after* a newer one and silently overwrite it with stale
   data. Fixed in two layers, both owner-implemented after being walked
   through the gap: (a) store the `Task` handle and `.cancel()` the
   previous one before starting a new one; (b) add `guard
   !Task.isCancelled else { return }` immediately after `calculate()`
   returns — belt-and-suspenders, since `.cancel()` alone doesn't
   guarantee `MKDirections.calculate()` actually honors Swift's
   cooperative cancellation internally, but the post-await guard
   guarantees correctness regardless.
3. *Duplicate source of truth* — the drop-point coordinate is hand-typed
   twice, independently, as both `CLLocationCoordinate2D.home` (View) and
   `CLLocation.home` (ViewModel). Flagged, not yet fixed — deliberately
   left as owner's call since it's a consistency risk, not a bug today.

**Good instinct:** asked *whether `Task.checkCancellation()` was also
needed* after already having correctly placed `Task.isCancelled` — shows
active verification of a completed fix rather than assuming "the review
comment is now satisfied," and led to a useful distinction (throwing vs.
non-throwing cancellation check, and which fits a non-`throws` function).

**Verified:** control UI click reflected in both the moving marker and an
updating route line; confirmed working via real `xcodebuild` builds after
each round of fixes, not just visual inspection.
