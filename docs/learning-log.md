# Learning Log

A running record of the concept-check quizzes at the end of each phase:
the question asked, the owner's raw answer verbatim, and Claude's
assessment/corrections/additions. Newest entries at the bottom.

See [CLAUDE.md](../CLAUDE.md) for the phase tracker and working process
this log supports.

---

## Phase 0 — Setup / Swift 6 strict concurrency

**Q:** Do you know offhand what the difference is between the *language
mode* setting (`SWIFT_VERSION = 6.0`) and *strict concurrency checking*
(`SWIFT_STRICT_CONCURRENCY`), and why a project could have one without the
other?

**Raw answer:**
> Swift 6 still supports approchable concurreny and without strict mode,
> concurrency issues will be highlighted as warnings not compile-time
> errors.
>
> on the other hand, keeping swift 5 and turning on strict concurreny will
> convert those warnings to errors but will lack additional language
> features and APIs as provided by swift 6

**Assessment / corrections:**
- Partially correct, with one real mix-up: `SWIFT_VERSION` (5 vs 6) is the
  actual on/off switch for errors vs. warnings. Swift 6 language mode makes
  data-race violations compile-time **errors**, full stop — there's no
  "Swift 6 without strict mode" that downgrades them back to warnings.
- `SWIFT_STRICT_CONCURRENCY` (minimal/targeted/complete) only does
  meaningful work in **Swift 5 mode** — it's the gradual-adoption dial.
  Even set to `complete` under Swift 5 mode, diagnostics stay **warnings**;
  it does not escalate to errors on its own. Only flipping `SWIFT_VERSION`
  to 6 does that.
- `SWIFT_APPROACHABLE_CONCURRENCY` + `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` is a separate axis: it changes *default isolation inference*
  (ordinary code implicitly runs on `MainActor` unless stated otherwise),
  reducing how often explicit `@MainActor`/`Sendable` annotations are
  needed. It does not relax error severity.

---

## Phase 1 — SSE fundamentals

**Q1:** If you deleted the blank line after each `data: ...` (so events
were just separated by a single `\n`), what would break, and why?

**Raw answer:**
> \n\n is a standard for streaming text telling the client that it can
> consume the packet of information received and doesn't have to wait
> anymore for the server to send the data.
>
> with a single \n, the client might want to wait further for the server
> response to process the current chunk of info

**Assessment / corrections:**
- Correct in spirit. Sharper framing: the `EventSource` parsing spec
  literally scans for a blank line to know a full event record is
  complete. Without it, multiple `data:` lines get coalesced into one
  still-pending event that never gets dispatched — not just delayed, but
  stuck in the parser's buffer indefinitely (until, if ever, a later blank
  line arrives).

**Q2:** Your `Connection: keep-alive` header — is that header actually
doing anything here, or is Node/Express already keeping the TCP connection
open by virtue of never calling `res.end()`? What do you think its role
really is?

**Raw answer:**
> My server itself is keeping the signal alive by not sending res.end(). I
> dont know the role of this header

**Assessment / corrections:**
- Correct that `res.end()` never being called is what actually keeps the
  connection open.
- `Connection: keep-alive` is mostly a **legacy holdover** from HTTP/1.0,
  which closed connections after every request by default. HTTP/1.1 (what
  Node's `http` module speaks) already defaults to persistent connections
  unless the server explicitly sends `Connection: close` — so on a modern
  stack this header is basically a no-op affirming behavior already
  present. Still commonly included as a defensive signal for older
  proxies/intermediaries. It's meaningless over HTTP/2, which forbids
  connection-specific headers entirely (multiplexing makes the concept
  moot).

---

## Phase 2 — Naive end-to-end pipe

**Q1:** If you open the control UI in two separate browser tabs at once
and click the map in one of them, what happens in the other tab? Walk
through why, based on how `connections` is used in `server.js`.

**Raw answer:**
> The connections are the ones listening to GET /stream endpoint while the
> controller UI POSTs to /location. We are not maintaining list of
> connections for the control UI. So, they operate as individual instances
> of the control UI and dont remain in sync. But they post to the same
> endpoint POST /location and events from both of them are relayed to the
> list of connected clients listening at GET /stream.

**Assessment / corrections:**
- Correct. Sharper framing: the control UI is currently **producer-only**
  — it never opens an `EventSource`/SSE connection back to `/stream`. The
  marker moving on click is purely optimistic (`marker.setLatLng()` set
  locally, before the `POST` even completes), not a reflection of server
  state. Two tabs are fully independent because neither is *listening*,
  only *sending*. The only shared state is the backend's `connections`
  array of actual `/stream` subscribers (currently just `curl -N`, later
  the iOS app). No conflict resolution exists if two tabs click
  simultaneously — last `POST` to land wins — which is fine for a
  single-rider toy app but worth naming.

**Q2:** What would currently happen if a client's `/stream` connection
died *without* the browser cleanly signaling a close (e.g. the process was
killed, or network dropped ungracefully) — would the `connections` array
still be accurate? What's the risk of it becoming stale?

**Raw answer:**
> If the client dropped ungracefully, the cleanup wouldn't execute and the
> res object will remain in the connection pool. Our POST /location
> endpoint will keep trying to push updates there but there will be no one
> to consume it.

**Assessment / corrections:**
- Correct, and there's a sharper edge worth knowing now even though the
  fix is deferred to Phase 7 (resilience): `req.on('close')` fires
  reliably on a *clean* disconnect (TCP FIN sent — tab closed, browser
  navigates away). On an *abrupt* disconnect (WiFi drop, client crash, no
  FIN), Node may not detect the dead socket until it actually tries to
  write to it — and that failed write emits an **`error` event
  asynchronously** on the response/socket. An `error` event with no
  listener is one of the few things that can crash a Node process outright
  (unlike most errors, unhandled `'error'` events throw rather than
  log-and-continue). So a stale, ungracefully-dropped connection isn't
  just wasted work sitting in `connections` — it's a live crash risk.
  Deferred to Phase 7, not fixed now.

---

## Phase 3 — Queue + rate-limited worker (conflation)

Backend was converted from plain JS to TypeScript during this phase (owner
request — see Amendments in the design spec). Implementation found a real
bug live: `types.d.ts` declared `ts: Date`, but the control UI actually
sends `Date.now()` (a `number`) through `JSON.stringify` — TypeScript
compiled cleanly anyway since it was just trusting the asserted type, not
validating the actual JSON payload. Fixed by changing the field to
`ts: number`, which matches what's really flowing through the system.

**Q:** Why does `req.body.ts` end up a plain `number` at runtime, even
though nothing in Express or TypeScript explicitly converts anything?
Where exactly does the "type information" actually come from and stop
applying?

**Raw answer:**
> req.body is parsed into a JSON and JSON doesn't have Date type. Also,
> the controller UI sends Date.now() which is the number of milliseconds
> (number type).
>
> Type checking doesn't produce / throw errors at network interface as
> typescript trusts our imposed type.

**Assessment / corrections:**
- Correct on both points: JSON has no `Date` type, and TypeScript trusts
  the asserted type at the boundary rather than checking it.
- One more layer worth having explicit: TypeScript types don't exist at
  runtime **at all** — they're fully erased by `tsc`. By the time `node`
  executes the compiled output, there is no `LocationUpdate` interface
  anywhere to check against, even in principle. `Request<{}, {},
  LocationUpdate>` is a compile-time lens imposed on `req.body`, not
  something verified. `express.json()` just calls `JSON.parse()` — it has
  no awareness of `LocationUpdate` and can't validate against it. This is
  why runtime boundary validation (parsing `unknown` into a checked type,
  e.g. with `zod`) is a distinct discipline from "having TypeScript types"
  — only one of them touches actual runtime data.

---

## Phase 4 — iOS client, no interpolation

This phase involved substantial real debugging beyond the formal quiz:
`AsyncThrowingStream` design (fixing a `startStreaming()` signature that
returned a single value instead of a continuous stream), a blank-line SSE
parsing bug that silently killed the stream after one event, a `URL`
typo (`/streaming` vs `/stream`), and a backend bug where `connections =
connections.filter(...)` reassignment orphaned the broadcast worker's
reference to the connections array after the first client disconnect
(fixed with `splice` to mutate in place). See
[progress-log.md](progress-log.md) for the full code-level account.

**Q1:** Why did `startStreaming()` need to become a function returning
`AsyncThrowingStream<LocationUpdate, Error>`, rather than something
simpler like `async throws -> [LocationUpdate]`? What's fundamentally
different about the two shapes?

**Raw answer:**
> Our goal was to open a long-lived connection where data can come in at
> non-fixed intervals and we processes it chunk by chunk as it arrives.
> SOmething like async throws -> [LocationUpdate] will just give us a
> piece of infomation once and no further updates are received.
> AsyncThrowingStream lets us use `for try await`, where we are
> persistently listening for async arrival of info pieces, and as a new
> piece arrives, we processes it.

**Assessment / corrections:**
- Correct. Sharper edge worth naming: it's not just less convenient — an
  `async throws -> [LocationUpdate]` signature would **never return at
  all** for a `/stream` connection with no natural end, since returning an
  array requires waiting for the sequence to finish first.
  `AsyncThrowingStream` has no such requirement; it hands over each value
  the instant it exists.

**Q2:** Why does `connections = connections.filter(...)` break the
broadcast worker specifically, when `connections.push(res)` earlier in the
same file never caused a problem?

**Raw answer:**
> splice mutates the array in place, while filter created a copy of the
> original array object and returned a new reference. Now, after filter,
> the connections are maintained at a new memory space while our worker
> is still looking for changes at the original memory space (original
> array). Hence, the changes never reach the worker. array.push() is a
> mutating function so that worked in the first hand.

**Assessment / corrections:**
- Correct and precisely stated. General principle worth carrying forward:
  whenever other code has captured a reference to a container (array,
  object) and needs to observe later changes, that container must be
  mutated in place — reassignment always creates a new object that only
  the reassigning code's own variable now points to, silently orphaning
  every other reference to the old one.

---

## Phase 5 — Route rendering (MKDirections)

Also covered informally during implementation: whether `Task.checkCancellation()`
was needed alongside the `Task.isCancelled` guard already added after
`requestMapRoute()`'s `await` (answer: no — `checkCancellation()` is the
throwing variant, useful inside an already-`throws` context; the plain
boolean check is the better fit for a non-throwing function that wants to
silently bail out rather than propagate a `CancellationError`). See
progress-log.md for the full implementation account (route recompute
decided intentional per-update, matching real ride-hailing apps; the
`routeTask` cancellation fix; the duplicate `.home` coordinate flagged).

**Q:** `MKDirections.calculate()` and `startStreaming()` are both `async`,
but one is a plain `async throws -> Response` call and the other returns
an `AsyncThrowingStream`. Why doesn't route-fetching need the stream
treatment the way the SSE connection did? What's the actual property of
the underlying operation that decides which shape is correct?

**Raw answer:**
> Route is a discrete piece of information which is derived from the
> rider location and the fixed home location. Everytime we get a new
> rider location, we can discretely calculate the route. Since its a
> network call therefore its async, but its like a plain GET request that
> delivers us the full information all at once.
>
> Whereas, the rider's coordinates are ever changing, hence we need a long
> held connection with the server. We dont know when the new update will
> be recieved. Thats something the server is sending to us, we are in a
> black box. The route however, is requested by us.
>
> And since we have attached the calculation of route with change in
> rider's corrdinates, we still have the right / fresh info all the time.

**Assessment / corrections:**
- Correct, and genuine transfer of the Phase 4 concept to a new situation
  rather than pattern-matching — the push/pull framing ("we are in a black
  box" for the server-driven stream vs. "the route is requested by us")
  is exactly the right mental model.
- One layer made explicit: the deciding factor isn't "does this happen
  more than once" (route fetching *is* called repeatedly, once per rider
  update) — it's **who initiates each exchange and whether it has a
  natural endpoint**. Each `calculate()` call is a complete,
  caller-initiated request→response cycle that finishes; N calls are N
  independent one-shot operations, not one continuous multi-valued
  operation. The rule: finite, caller-initiated, one-answer-per-call →
  plain `async`. Indefinite, producer-driven, many-answers-per-call → a
  stream.

---

## Phase 6 — App restructure (Rider/Customer navigation)

**Q:** In the design we agreed on, `topic` is a pub/sub routing key —
multiple riders and multiple customers can all key off the same topic
string simultaneously, with no real auth or per-order semantics behind it.
Does "orderID" as a label match that concept, or does it imply
something narrower/different? If different, does that difference actually
matter for how the backend (Phase 7) or the rest of the app should treat
this value?

**Raw answer:**
> To keep things simple for now and also relate to real world, I am
> interchangibly using topic with order ID. This is to show how there's a
> publisher and a subscriber for a given active order - and they publish
> on / consume from a topic. In reality, i feel an order ID can have
> multiple topics - for location updates, status updates, payment updates
> etc.

**Assessment / corrections:**
- Correct, and the elaboration is the sharp part: in a real system an
  entity like an order typically fans out across a **family** of topics
  rather than owning just one (e.g. `orders.{orderId}.location`,
  `orders.{orderId}.status`, `orders.{orderId}.payment`), matching how
  Kafka/pub-sub systems are usually namespaced — one topic per *event
  stream*, not per *entity*. Using orderID as a stand-in for the single
  topic this emulator models (location updates only) is a reasonable
  simplification, with the real-world gap correctly identified rather than
  papered over.

---

## Phase 7 — Backend multi-tenancy (per-topic queue/worker/connections)

**Q:** During the design discussion, we chose per-topic queue + worker +
connections (each topic gets its own independent trio) over the
alternative — one shared queue + one shared worker, where every item is
tagged with its topic and a single loop routes it to the right
subscribers. Now that you've actually built the per-topic version: what
specifically would go wrong (or get worse) with the shared-queue
alternative, in terms of the behavior your `curl` tests just exercised?

**Raw answer:**
> In case of the shared queue, firstly, we'll need to maintain a pair of
> {topic, request} instead of per-topic request pool. Then, whenever a new
> location /POST request comes in, we'll have to iterate over the request
> pool and filter requests and stream to all those requests. It will add
> time complexity and can induce delays in high traffic scenarios. Its
> much more difficult to maintain.
>
> Is there anything i am missing?

**Assessment / corrections:**
- The filtering-overhead/maintenance-complexity point is real, but the
  bigger issue is **correctness, not just performance** — and it's exactly
  what the burst-conflation `curl` test exercised. The current conflation
  logic (`getRecentItem()` + `empty()` each tick) means "keep only the
  single most recent item, discard the rest." That's safe today because
  each `DummyQueue` only ever holds one topic's items. In a shared queue,
  the same logic would keep only the single most recent item **across all
  topics** — if `order-A` and `order-B` both get an update in the same
  tick, whichever landed last survives and the other topic's update is
  **silently and permanently dropped**, not delayed. Fixing that requires
  conflation to become "latest item per topic key" (e.g. a `Map<topic,
  item>`), which just reinvents per-topic separation with extra
  indirection instead of avoiding it.
- Second angle, tied to the actual design rationale ("so one busy topic
  can't starve another's dispatch timing"): `DummyQueue`'s fixed 100-item
  cap evicts the *oldest* item once full. In a shared queue, a bursty
  topic filling toward that cap could evict a quiet topic's not-yet-
  broadcast item first — a noisy-neighbor problem the per-topic design
  avoids by construction, since each topic gets its own independent
  eviction budget.
- Owner explicitly asked "is there anything I'm missing" rather than
  treating the first-pass answer as complete — good instinct, consistent
  with the Phase 5 pattern of actively checking a completed fix rather
  than assuming a review comment is satisfied.

---

## Phase 8 — Rider client (producing into a topic)

**Q:** You initially tried adding `Task` cancellation to `RiderView`'s tap
handler — cancel any in-flight send before starting a new one — mirroring
the pattern from Phase 5's route-fetching. After walking through it, you
removed it and went back to plain fire-and-forget `Task { }` blocks with no
cancellation. In your own words: why is a Rider's location POST safe to
fire-and-forget, with no client-side ordering or cancellation logic at all,
when Phase 5's route fetch specifically needed that protection?

**Raw answer:**
> The correct update handling happens on the server side (as it should
> be).
>
> Also, a question for you - can there could still be a scenario where a
> slow rider connection can lead to mixed up updates? Shouldn't the queue
> ideally be a priority queue sorted over ts - highest first? Just
> curious

**Assessment / corrections:**
- Correct on the core distinction: Phase 5 needed cancellation because the
  *client* derived visible state directly from whichever response arrived
  last (`self.route = route`); an out-of-order response would visibly
  corrupt the map. A Rider's POST doesn't do that — nothing client-side
  depends on send/completion order, because the backend's per-topic
  conflation worker is the thing that decides which update wins.
- The follow-up question is a genuinely sharp catch, not just curiosity:
  `DummyQueue.getRecentItem()` returns `this.queue[this.queue.length - 1]`
  — the last item **enqueued**, i.e. arrival order — not the item with the
  highest `ts`. Since taps fire independent, unawaited `Task`s, a slow or
  lossy connection really can deliver an older-`ts` update *after* a
  newer one, and the current design would let the older one win. Arrival
  order and event-time order are quietly being treated as the same thing,
  and they aren't.
- Where the proposed fix overshoots: a priority queue pays for maintaining
  full sorted order (`O(log n)` insert) to support repeated ranked
  extraction — but `broadCastLocation` extracts the max once and then
  calls `queue.empty()`, nuking the whole collection every tick. Nothing
  ever needs ranked access beyond "the single freshest item, right now."
  A running comparison on `enqueue` (`O(1)`, keep the item only if its
  `ts` beats the current max) gets the same correctness with less
  machinery than what exists today, let alone a heap.
- Parked for Phase 12: the low-network reconnect flush will fire a burst
  of individual POSTs, which is exactly the "several updates racing the
  server, possibly out of order" scenario this question describes —
  turning it from a theoretical edge case into one Phase 12 will likely
  trigger for real.

---

## Phase 9 — Customer client + Google Maps SDK swap

**Q:** In your own words — why did both the marker *and* the polyline need
to go through the `Coordinator`, instead of just being created fresh
inside `updateUIView` every time it runs? What would you actually have
seen on screen if you'd skipped the Coordinator and just done
`GMSMarker(position: riderCoordinate).map = uiView` directly inside
`updateUIView`, with no `if let`/`else` check at all?

**Raw answer:**
> Multiple markers overlapping - basically a new marker everytime
> updateView would have ran (on each state update). Coordinator helps
> manage stuff that needs to persist across instance creations
> (UIViewRepresentable instances) whenever SwiftUI rerenders and
> recomputes the views.

**Assessment / corrections:**
- Correct on the core mechanism. One sharpening on the visual outcome:
  not quite "overlapping" — `updateUIView` only re-runs *because*
  `riderCoordinate` changed to something new each time, so a fresh
  marker created at the current coordinate on every call would produce a
  breadcrumb trail of abandoned markers at each of the rider's past
  positions, never removed, rather than a pile stacked at one point.
- One terminology precision worth having, since it's foundational to
  value vs. reference semantics generally: a struct has no "instances"
  with identity the way a class does. Every SwiftUI re-render produces a
  completely fresh, independent `GoogleMapsViewRepresentable` value,
  unrelated to the previous one. The `Coordinator` isn't surviving
  *between* instances of the struct — it's the one deliberately
  reference-typed piece of state SwiftUI keeps alive and hands back
  across an otherwise fully disposable, stateless sequence of struct
  values.

---

## Phase 10 — Client-side interpolation (route-snapped, CATransaction)

**Q:** In your own words: what actually caused the overshoot-and-drift bug
— specifically, what caused `updateUIView` to fire a second time for the
same rider coordinate, with nothing new having actually arrived from the
backend?

**Raw answer:**
> Not sure on this

**Assessment / corrections:**
- Genuinely subtle, full explanation given rather than a quiz correction.
  Core mechanism: `updateUIView` doesn't fire "when `riderCoordinate`
  changes" specifically — it fires whenever SwiftUI rebuilds the
  `GoogleMapsViewRepresentable` value at all, for *any* reason, because
  `CustomerView.body` reads all three of the representable's source
  properties (`riderCoordinate`, `homeCoordinate`, `route`) off an
  `@Observable` view model. A change to *any* of them re-runs the body and
  produces a new representable value, which SwiftUI diffs and calls
  `updateUIView` on — regardless of which property actually changed.
  Sequence: rider update → `riderLocation` changes → `updateUIView` fires,
  animation starts → separately, the async route request from that same
  update resolves *later* → `route` changes → `updateUIView` fires again,
  with `riderCoordinate` unchanged — but the old code had no way to
  distinguish "called because something new happened" from "called
  because anything changed," so it re-ran the full snap-and-animate
  sequence for the same target, now measured against the newly-changed
  polyline. The small mismatch between the old-polyline-snap and the
  new-polyline-snap *is* the overshoot-and-drift.
- General lesson, extending Phase 9's lifecycle doc: `updateUIView` tells
  you a representable's properties *might* have changed, not *which* one
  did. Reacting differently depending on what actually changed requires
  tracking "the last value reacted to" yourself (`lastKnownTarget`) and
  diffing against it — SwiftUI does not make that distinction for you.
- Also this phase, not separately quizzed but worth recording: owner
  redirected the phase's focus from manual lerp/Timer math (the originally
  speced approach) to route-snapped interpolation (nearest-point-on-
  polyline snapping, sub-path slicing, proportional per-segment
  `CATransaction` chaining) after choosing `CATransaction`'s built-in
  position animation over hand-rolling the interpolation math — a
  deliberate trade so effort went into the harder, more realistic
  "follow the road through a U-turn under sparse updates" problem instead
  of reinventing lerp. Also added threshold-gated route recompute (only
  refetch via `MKDirections` once the rider drifts >20m off the existing
  route, `MKPolyline.distance(to:)`) — owner's own idea, correctly
  identified as addressing the overshoot bug's root cause (unnecessary
  route recomputes) rather than just its symptom.

---

## Phase 11 — Realism upgrade (adaptive duration, bearing, camera framing)

**Q:** Bearing is computed *per segment* of the animated sub-path (inside
`animateMarker`'s loop), not once for the whole rider update using just the
start and end coordinates. Why does that matter specifically for the
U-turn scenario Phase 10 was built around — what would the marker visibly
look like during a turn if bearing were computed only once, from the
update's start point straight to its end point?

**Raw answer:**
> One rider update can have non-linear segments - like a u-turn or just a
> curvy road. Bearing is computed per segment to always make sure the
> marker image (car) is facing in the direction of the road it is on and
> doesn't look like its drifting apart.

**Assessment / corrections:**
- Correct, and the right mechanism identified: a single update's path can
  span multiple segments with genuinely different directions, so one
  bearing value can't represent all of them.
- Sharper picture worth having: if bearing were computed once from the
  sub-path's raw start-to-end straight line, the marker would lock into
  that fixed rotation for the *entire* multi-segment animation — even as
  its actual position correctly curves through the turn (Phase 10's
  route-snapping). During the sharpest part of a U-turn you'd see the car
  visibly moving sideways or backwards relative to which way it's facing,
  worst exactly where the road curves most — the same U-turn case that
  motivated Phase 10's redirect in the first place. Position and
  orientation are two independent things the marker needs to get right
  per segment, not just one.
