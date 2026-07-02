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
