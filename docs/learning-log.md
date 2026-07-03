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
