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
