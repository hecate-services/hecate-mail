# PART 1 — Vision & Architecture

## The gap this fills, precisely

Verified live, not assumed, on 2026-08-29 while working on `macula-io/macula-mcp`:

```
$ macula-cli --help
macula-cli — test, monitor, and diagnose the Macula mesh

Usage:
  macula-cli connect <host[:port]>
  macula-cli call <host[:port]> <procedure>
  macula-cli pubsub watch <host[:port]> <topic>
  macula-cli pubsub publish <host[:port]> <topic>
  macula-cli stream probe
  macula-cli content probe <host[:port]>
  macula-cli content put <host[:port]> <file>
  macula-cli content get <host[:port]> <mcid>
  macula-cli identity
```

`call` is the only RPC verb, and it is requester-only. There is no
`advertise`. Every agent using `macula-mcp` (Claude Code, Cursor, any MCP
client) can ask the mesh to do something, but can never itself be the thing
asked — and neither can any other ephemeral Claude Code session, because a
CLI-driven chat session isn't a standing process even if advertising existed.

Two consequences an agent hits immediately:

1. **No discovery.** `mesh://peers` was deliberately dropped from
   `macula-mcp`'s design (not merely unbuilt) because `macula-go-sdk` has no
   peer-listing API to wrap. There is no "who's out there" query anywhere in
   the stack today.
2. **No delegation.** Even knowing a specific person's identity, there's
   nothing to call — their Claude Code session isn't listening, and nothing
   they run today advertises a procedure on their behalf while they're away
   from the keyboard.

`hecate-mcp-mail` is a real, always-on citizen that fixes both: it maintains
the directory (1), and it gives every citizen an address that holds mail for
them until they're back (2).

## Correct vocabulary — this matters, get it right from the first commit

`hecate_om`'s own `identity_model.md` draws a distinction this plan follows
exactly, because getting it backwards produces a design that tries to make
services "peers of citizens" instead of infrastructure citizens rely on:

| | **Citizens** | **Institutions** |
|---|---|---|
| Who | Users — a person's Claude Code session, `hecate-daemon`, any MCP client acting on someone's behalf | Services — `hecate-rag`, `hecate-llm`, and now `hecate-mcp-mail` |
| Credential | Realm-issued personal cert, mortal and mobile | Realm-issued service-principal cert, persistent, "the badge stays with the building, not the person" |
| Runs on | A citizen's own laptop/session | Realm-owned infrastructure — never a citizen's laptop |
| What "directory" means here | The set of *citizens* who have registered a mailbox (people/agents reachable this way) | N/A — institutions don't need a directory of each other for this use case |

So: **the "citizens directory" this service maintains is a directory of
*users*, not of services.** When the original question was "show other
macula citizens," the honest Hecate-vocabulary answer is "show the other
people (and their agents) who've registered a mailbox here" — not a service
registry. Keep this straight in every desk/module name that follows.

## What already exists — study this before writing a line of domain code

Per this workspace's own standing rule (`CLAUDE.md` §4, "Deep-Study
Dependencies When Source Available"), the following was read in full before
this plan was written, not skimmed:

- `hecate-om/guides/service_anatomy.md` — the six-callback `hecate_om_service`
  contract, the `rebar3 new hecate_service` template, optional `store_id/0`+
  `data_dir/0` (reckon-db event store) and `read_model_id/0`+`data_dir/0`
  (`barrel_docdb` read model) wiring.
- `hecate-om/guides/mesh_native_services.md` — how to serve an RPC
  (`capabilities/0` + a `macula_response` handler, auto re-advertised every
  30s via `advertise_direct`), how to call one (`hecate_om:call_capability/4`),
  how to publish/subscribe (`hecate_om_pubsub`), and the wire-level gotcha
  that reply/arg keys arrive as atoms via `hecate_om_wire:field/2,3`.
- `hecate-om/guides/read_model_services.md` — the Listener → Policy →
  Projection split (`hecate-stations` shipped without it once and had to add
  it back), the TTL-based admit/stale pattern that gives staleness handling
  "for free" from the same republish mechanism that keeps a DHT record alive,
  and the live gotcha that `hecate_om_capabilities`'s 30s re-advertise cadence
  does NOT shorten the advertisement's TTL — a dead service still looks
  callable for up to 48h unless `ttl_ms` is passed explicitly.
- `hecate-om/guides/identity_model.md` — the citizen/institution split above,
  service-principal scoping via `identity_spec/0`, and the v1/v2 credential
  roadmap (long-lived realm-signed cert now, short-lived UCAN later).
- `hecate-services/hecate-stations` (the real running example both
  `read_model_services.md` and `service_anatomy.md` are extracted from) — read
  `hecate_stations_service.erl`, `hecate_stations_app.erl`, and
  `hecate_stations_sup.erl` directly, not just the guide's excerpts.

**None of the mesh wiring, capability advertisement, health endpoint, realm
identity, or (if used) event-store/read-model boot sequence needs to be
built here.** `hecate_om:boot/1` does all of it from the six-callback
contract plus whichever optional callbacks this service exports. What this
plan actually specifies is: which capabilities to declare, what the
Listener/Policy/Projection chain looks like for the directory, and what the
CMD/PRJ aggregate shape is for mailboxes.

## The two-piece shape

```
                         hecate-mcp-mail (one OTP release, one container)
                         ┌──────────────────────────────────────────────┐
                         │                                              │
   register_citizen ───▶ │  CITIZENS DIRECTORY (read-model, no store)   │
   (RPC, self-serve)     │  - barrel_docdb, like hecate-stations        │
                         │  - fed by: local self-registration           │
   citizen_presence  ───▶│           + federated facts from other       │
   (pubsub, federation)  │             hecate-mcp-mail instances        │
                         │  - TTL/republish based staleness (§ PART2)   │
   list_citizens    ◀─── │                                              │
   get_citizen      ◀─── │                                              │
                         ├──────────────────────────────────────────────┤
                         │                                              │
   deposit_letter   ───▶ │  MAILBOXES (event-sourced CMD/PRJ)           │
   (RPC, from any        │  - reckon-db store (this service owns it)    │
    citizen, routed      │  - mailbox-{did} aggregate stream            │
    via directory's      │  - CMD: deposit / mark_read / reply / archive│
    hosted_at field)     │  - QRY: get_mailbox_by_citizen, get_letter   │
                         │  - letters do NOT federate (§ decisions log) │
   get_mailbox      ◀─── │  - caller-identity check on read: OPEN       │
   (RPC, owner only)     │    QUESTION, see PART3                       │
                         │                                              │
                         └──────────────────────────────────────────────┘
```

Both pieces are exposed the same way — `capabilities/0` entries with
`handler => {Module, Args}` — so from `macula-mcp`'s side, every operation
above is just an ordinary `mesh_call`. Nothing about this design requires or
benefits from macula-mcp changes; see PLAN_ROOT.md's closing note.

## Naming, per this workspace's own conventions

Given the mail/citizens domain isn't one of the 10 canonical Hecate
processes (it's user-domain-shaped, broad lifecycle per entity), the
`manage_` prefix is the explicitly-allowed case per `CLAUDE.md`'s own naming
table ("User domain code: prefer specific verbs, allow `manage_` when the
scope is genuinely broad — multiple operations on one entity lifecycle").

| App | Kind | Owns |
|---|---|---|
| `hecate_mcp_mail` | Service shell (generated) | Boot, `hecate_om_service` callbacks, health, capability list |
| `manage_mailboxes` | CMD | `deposit_letter/`, `mark_letter_read/`, `reply_to_letter/`, `archive_letter/` |
| `query_mailboxes` | QRY+PRJ | `get_mailbox_by_citizen/`, `get_letter_by_id/`, the `letter_*_v1_to_mailboxes` projections |
| *(citizens directory)* | Lives directly in `hecate_mcp_mail` alongside the service module, hecate-stations-style — no separate CMD/QRY app, since it's pure read-model mirroring plus one self-serve RPC, not a rich command lifecycle | `register_citizen` handler, the Listener/Policy/Projection triple, `list_citizens`/`get_citizen` handlers |

See PART2 and PART3 for the full desk/command/event lists.
