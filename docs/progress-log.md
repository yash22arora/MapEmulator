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

---

## Phase 6 — App restructure (Rider/Customer navigation)

**Context:** first phase of the 2026-08-14 scope expansion (see Amendments
in the design spec) — single-client app retargeted into Rider/Customer
roles sharing one Xcode target, selected from a home screen alongside a
shared `topic` string. This phase is navigation/state-passing scaffolding
only; no real Rider/Customer behavior yet (that's Phases 8-9).

**Owner-written:** `Destination` enum (`Hashable`, `.rider(topic:)` /
`.customer(topic:)` cases) replacing `HomeView`'s old bare-`String`
`NavigationPath`; `TextField`-bound `topic` state plus two buttons
(non-empty guard before navigating); `navigationDestination(for:
Destination.self)` switch dispatching to `RiderView(topic:)` or
`CustomerView(topic:)`. `LiveView.swift` renamed to `CustomerView.swift`
(kept its existing MapKit/route logic as-is, since that gets reworked in
Phase 9 anyway) rather than left parked as originally suggested — the
owner's call, and a reasonable one since the file didn't need to sit idle.
New `RiderView.swift` scaffolded as a minimal MapKit view stub, no
producer logic yet.

**Review notes, both owner-fixed before the phase closed:**
1. `RiderView.swift`'s file header comment still read "CustomerView.swift"
   — copy-paste leftover from cloning the file, cosmetic only.
2. First draft of `RiderView` rendered a "Rider" annotation off
   `viewModel.riderLocation`, copied over from `CustomerView`/`LiveView` —
   but `RiderView` never calls `startFetchingRiderLocation()`, so the
   branch was dead code. Removed, replaced with a placeholder comment for
   Phase 8.

**Verified:** real Xcode build succeeded; `HomeView` → topic entry → both
`RiderView` and `CustomerView` push correctly with the topic reflected in
each nav title. Committed and pushed by the owner.

---

## Phase 7 — Backend multi-tenancy (per-topic queue/worker/connections)

**Owner-written:** `TopicChannel<T>` (`backend/src/TopicChannel.ts`) —
generic class bundling one topic's `DummyQueue<T>`, `Set<Response>`
connections, and its own idempotent `start()`/`stop()` broadcast interval;
`getOrCreateTopicChannel` registry (`backend/src/services.ts`) backed by a
`Map<string, TopicChannel<LocationUpdate>>`, lazily creating channels from
either endpoint; `server.ts` rewired so `POST /location` and `GET
/location/stream` (renamed from `/stream` mid-phase, see Amendments in the
design spec) both resolve a topic-scoped channel instead of touching
module-level
singletons, with request validation (400 on missing `topic`/fields) added
to both. Good instinct, unprompted: swapped `connections` from `Response[]`
to `Set<Response>`, closing the `indexOf`-returns-`-1` edge case flagged
(but never hit) back in Phase 4's disconnect-handling review — `Set.delete`
needs no index lookup at all.

**Claude-scaffolded (tooling, not a learning target):** added a topic text
input to the Leaflet control UI (`backend/public/index.html`) and wired it
into the existing `POST /location` call, matching the same "boilerplate
handed over directly" precedent as the original Leaflet wiring in Phase 2.

**Design iteration on `TopicChannel`, guided but owner-implemented:**
1. First draft hardcoded `implements ITopicChannel<LocationUpdate>` with a
   separate, non-generic interface. Reworked to a true generic
   (`class TopicChannel<T> implements ITopicChannel<T>`), motivated by the
   Phase 6 quiz insight that a real order could have multiple topic
   families (location/status/payment) — this class no longer needs to know
   its payload type.
2. Attempted to mark `started` `private` while it was still declared in
   `ITopicChannel` — hit a genuine TypeScript rule most people don't
   expect: an interface can only describe a type's *public* members, so a
   class implementing it cannot narrow a declared member to `private`.
   Fixed by removing `started` from the interface entirely (it was never
   part of the public contract — internal-only bookkeeping for whether
   `start()` had already fired), not by working around the access
   modifier.

**Bugs found during review, both owner-fixed:**
1. `stop()` set `this.started = false` but never captured the
   `setInterval` handle anywhere, so it couldn't actually `clearInterval`
   — the timer kept running regardless. A later `start()` call would have
   spun up a *second* concurrent interval against the same queue/
   connections, silently double-broadcasting — exactly the failure mode
   the `started` guard existed to prevent, just via a different path.
   Fixed by storing `intervalId` on the instance and clearing it in
   `stop()`.
2. `const topic = req.query.topic as string` — a type assertion, not a
   runtime check. Express types `req.query.topic` as
   `string | ParsedQs | (string | ParsedQs)[] | undefined`; the cast would
   have let a malformed query string (e.g. `?topic=a&topic=b`, parsed as an
   array) flow through as if it were a plain string with no error at any
   point. Same category of bug as Phase 3's `ts: Date` vs. `ts: number`
   mismatch — a type-level assertion standing in for an actual runtime
   check. Fixed with `typeof req.query.topic !== "string"` narrowing
   instead of a cast.
3. Vestigial module-level `connections`/`queue` singletons left in
   `server.ts` after the registry rewire (self-flagged by the owner with a
   `/// To be deleted` comment, confirmed genuinely unused, then removed).

**Design discussion, not a bug:** `TopicChannel.start()` is only invoked
from `GET /location/stream`, and the owner added `stop()` on the last subscriber's
disconnect — so a topic's broadcast interval only runs while at least one
customer is connected. Deliberate efficiency choice, discussed and kept:
the trade-off is that `POST`ed updates during a subscriber-less gap sit
unconflated in the raw queue (up to `DummyQueue`'s 100-item cap, oldest
evicted first) rather than being conflated away each tick, and a
reconnecting customer still only ever sees the single latest point, not a
catch-up of what happened — consistent with the project's existing
"live-edge only, no replay buffer" stance, just made concrete here rather
than hypothetical.

**Verified:** `tsc --noEmit` clean; manual `curl` pass — two concurrent
`GET /location/stream` subscriptions on different topics confirmed isolated (a
`POST` to one topic never appeared on the other's stream), burst-POST
conflation confirmed per-topic via topic-labeled console logs, both
missing-`topic` validation paths returned 400, and the disconnect →
`removeConnection` → `stop()` path did not crash the server. Browser
control UI re-verified end-to-end with the new topic field.

---

## Phase 8 — Rider client (producing into a topic)

**Owner-written:** `RiderView`'s tap-to-select flow — `MapReader` +
`.onTapGesture { screenPoint in ... }` + `proxy.convert(_:from:)` to turn a
tap into a `CLLocationCoordinate2D`, rendered as a pin `Annotation`;
`RiderViewModel` (new, mirroring `LiveViewViewModel`'s DI shape) wrapping
`LiveViewDataManaging` and exposing `sendLocationUpdate(location:)`;
`LocationUpdate` model widened from `Decodable` to `Codable` with `topic`
added, so it can be encoded for outgoing POSTs, not just decoded from SSE.

**Claude-scaffolded (explicitly requested, boilerplate/setup syntax, not a
learning target):** `LiveViewDataManager.sendLocationUpdate` — the actual
`URLRequest`/`JSONEncoder`/`URLSession.shared.data(for:)` POST mechanics.
Simplified its signature from a first draft of
`throws -> Result<Any, any Error>` (redundant — throwing *and* returning a
`Result` makes callers handle two error channels for one failure) to plain
`async throws`, matching the pattern `requestMapRoute()` and
`startStreaming()` already established in this codebase.

**Design iteration on `RiderView`, guided but owner-decided:**
1. First attempt used `.onChange(of: selectedCoordinate)` to trigger the
   send, which doesn't compile — `CLLocationCoordinate2D` isn't
   `Equatable`, which `onChange` requires. Rather than add a retroactive
   `Equatable` conformance, moved the send call directly into the tap
   handler instead, since `selectedCoordinate` only ever changes from that
   one call site anyway. This also fixed a real behavioral gap the
   `onChange` version would have had: tapping the same spot twice in a row
   wouldn't have fired a second send, since `Equatable` would report no
   change.
2. Attempted `Task` cancellation on the tap handler (cancel any in-flight
   send before starting a new one), mirroring Phase 5's route-request
   pattern. Had three compile-level issues (a non-`@State` `var` that
   resets on every view re-render since `RiderView` is a struct; a
   shadowing `let task` inside the closure that never actually assigned to
   `self.task`; a `Task<Void, Error>` type that didn't match
   `sendLocationUpdate`'s non-throwing `async` signature) — but the
   deeper issue surfaced in the Phase 8 quiz (see learning-log.md): this
   scenario doesn't need cancellation at all, since no client-side state
   is derived from send order the way Phase 5's `route` assignment was.
   Removed in favor of plain fire-and-forget `Task { }` blocks.

**Verified:** structurally reviewed against the Phase 7 backend
(`http://localhost:3000/location`, later swapped to the ngrok tunnel — see
the tooling entry below); owner confirmed a real device build/run.

---

## Between phases — HomeView redesign & ngrok device-testing setup

Not tied to a specific phase's core concept — requested directly as
tooling/infrastructure work, in the same spirit as the Leaflet control
UI being handed over in Phase 2.

**Claude-built, at the owner's request:**
- **`HomeView` visual redesign** — native SwiftUI only (no custom assets):
  icon mark, proper type scale (`.largeTitle`/`.subheadline`/`.caption`),
  a styled topic field instead of a bare unstyled `TextField`, color-coded
  role buttons (`.borderedProminent`/blue for Rider,
  `.bordered`/green for Customer) disabled until a topic is entered.
  Caught and fixed a real bug while rewriting: `NavigationStack { ... }`
  wasn't bound to the `@State private var path`
  (needed `NavigationStack(path: $path)`), so `path.append(...)` was
  almost certainly a no-op — meaning Phase 6's "navigation confirmed
  working" note likely only ever confirmed the build compiled, not that
  tapping actually navigated. Not retroactively edited in the Phase 6
  entry above, per this log's practice of recording history as it was
  understood at the time; noted here instead.
- **ngrok tunnel for real-device testing** — Mac too slow to run the
  Simulator usably. Updated the owner's ngrok install (3.5.0 → 3.39.11;
  the old version failed account auth outright). Centralized the two
  scattered `http://localhost:3000` string literals in
  `LiveViewDataManager` into a single `BackendConfig.baseURL`, now pointed
  at the ngrok HTTPS forwarding URL — one-line swap for when the free-tier
  URL next rotates, or back to `localhost` for Simulator use. Verified the
  tunnel round-trips via `curl` (`GET /`, `POST /location`, and
  `GET /location/stream`) before pointing the app at it. Added an
  `ngrok-skip-browser-warning` header to both client requests as a
  defensive measure against ngrok's free-tier interstitial page — tested
  and found it wasn't actually triggering on this account/tier, so the
  header is precautionary rather than a confirmed fix for an observed
  problem.
