# hecate-mcp-mail — Plan Index

**Status: Planning. Scaffold generated (`rebar3 new hecate_service`), builds. No
domain code written yet — this plan is the specification for it.**

## One-line answer to "why does this exist"

`macula-mcp`'s tools (`mesh_call`, `mesh_publish`, `mesh_watch`, ...) can *call*
something already advertised on the mesh, but nothing in `macula-cli` can
*advertise* — so an agent has no way to reach another party who isn't already
running a real service, and no way to find out who else is even out there.
`hecate-mcp-mail` is that missing piece: a real, standing Hecate service (an
institution, not a laptop) that (1) keeps a directory of citizens who've
registered a mailbox, and (2) lets one citizen drop an addressed letter for
another who isn't online right now, so delegation across two ephemeral Claude
Code sessions in different timezones is actually possible.

## How this came about

Traced directly from a live conversation on `macula-io/macula-mcp`
([[project_macula_mcp_track]] in memory), 2026-08-29:

1. User asked whether `macula-mcp` could show other "macula citizens," whether
   automated planetary agent-to-agent communication was buildable, and
   concretely whether their Claude could ask a Claude Code user in the US to
   do work for them.
2. Investigation found the real, verified blockers: `macula-cli` has no
   `advertise` command (confirmed via `macula-cli --help` — `connect / call /
   pubsub / stream / content / identity`, nothing that registers a callable
   procedure), `mesh://peers` was deliberately dropped from `macula-mcp`
   because `macula-go-sdk` has no peer-listing API, and a Claude Code session
   is interactive/ephemeral, never a standing listener.
3. User proposed a `hecate-services/hecate-mcp-postoffice` edge service to
   fill the gap, named it `hecate-mcp-mail` on reflection, and asked mid-plan
   for two more things folded in here: (a) multiple `hecate-mcp-mail`
   instances should sync via mesh facts rather than requiring one centralized
   instance, and (b) noted a sibling idea, `hecate-services/hecate-mcp-agora`
   (a public square, not an addressed mailbox) — **out of scope for this
   repo, see [§ Relationship to hecate-mcp-agora](#relationship-to-hecate-mcp-agora-not-built-here) below.**

## Parts

| Part | Covers |
|---|---|
| [PART1 — Vision & Architecture](PLAN_HECATE_MCP_MAIL_PART1_VISION_AND_ARCHITECTURE.md) | The `hecate_om` substrate this is built on, correct Hecate vocabulary (citizen vs. institution), the two-piece shape (directory + mailboxes), what already exists vs. what this repo adds |
| [PART2 — Mail-Location Directory](PLAN_HECATE_MCP_MAIL_PART2_MAIL_LOCATION_DIRECTORY.md) | **Revised:** identity moved to [`hecate-citizens`](https://github.com/hecate-services/hecate-citizens); this part now covers only the thin mail-routing directory (which instance hosts a citizen's mailbox), federation via mesh facts, Listener/Policy/Projection, TTL-based staleness |
| [PART3 — Mailboxes](PLAN_HECATE_MCP_MAIL_PART3_MAILBOXES.md) | Event-sourced CMD/PRJ design, aggregate/stream shape, commands/events, QRY desks, the open caller-identity-verification question flagged honestly, not hand-waved |
| [PART4 — Deployment, Security, Roadmap](PLAN_HECATE_MCP_MAIL_PART4_DEPLOYMENT_SECURITY_ROADMAP.md) | Why this can't run on a laptop, service-principal provisioning, what's explicitly deferred, phased build order |

## Decisions log

| Date | Question | Decision |
|---|---|---|
| 2026-08-29 | Build on `hecate_om`, or wire macula directly? | **`hecate_om`.** It already solves mesh wiring, capability advertisement + re-advertise, realm identity, and optional reckon-db/barrel_docdb wiring — every one of those was a real, separately-discovered bug in some other service before `hecate_om` existed (see its own `guides/`). Reinventing any of it here would be re-walking ground already paved. |
| 2026-08-29 | One service or two (directory vs. mailboxes)? | **One service, two internal concerns.** Same repo, same OTP release — `hecate-stations` already proves a single service can be read-model-only; this one additionally owns a `reckon-db` store for mailboxes. Splitting into two deployable services is possible later if operational reasons demand it, not designed in from day one on spec. |
| 2026-08-29 | Does mail content get federated across instances? | **No — only presence/directory facts federate.** A letter lives solely on the instance the recipient is registered at (learned from the federated directory's `hosted_at` field); depositing means calling that specific instance directly, not broadcasting the letter itself. Federating letter contents would mean every instance holds a copy of everyone's mail, which is a real privacy regression nobody asked for. |
| 2026-08-29 | Where does this run? | **Realm-owned infrastructure, not a user's laptop** — `hecate_om`'s own `identity_model.md` is explicit that a Hecate service is an institution with its own service-principal credential, never a citizen-bound process. See PART4. |
| 2026-08-29 | Should identity (the citizens directory) live in this repo? | **No, moved to [`hecate-citizens`](https://github.com/hecate-services/hecate-citizens).** The moment `hecate-mcp-agora` was named as a real next consumer of the same identity data, keeping it embedded here meant two services would each federate their own copy — a real divergence risk, not a hypothetical one. Extracted before either service's directory code existed, not after. "One more standing service" was raised and explicitly rejected as a reason not to — this ecosystem is already collaborating microservices, and a shared directory used by more than one of them is exactly what that architecture is for. This repo now owns only mail-specific routing (which instance hosts a mailbox) — see PART2. |

## Relationship to `hecate-citizens`

This repo depends on [`hecate-citizens`](https://github.com/hecate-services/hecate-citizens)
for identity (is this DID a known citizen, what's their display name) —
see PART2 for the revised split. `hecate-mcp-mail` does not embed or
federate its own copy of that data; it keeps only its own mail-specific
routing directory (which instance hosts a citizen's mailbox).

## Relationship to `hecate-mcp-agora` (not built here)

The user separately floated `hecate-services/hecate-mcp-agora` — a public
square (post publicly, anyone reads, no addressing), the broadcast
complement to this repo's addressed mailbox. It's a real, well-shaped sibling
idea (same shape as `hecate-spartan`'s own `publish_to_agora` concept,
generalized), and it would depend on `hecate-citizens` for identity the
same way this repo now does. **Deliberately not scaffolded or planned
here** — the task that produced this repo was specifically
`hecate-mcp-mail`; agora deserves its own plan, written when it's actually
being started, not bolted onto this one to save a conversation turn.

## Relationship to `macula-mcp`

**Zero changes needed to `macula-mcp` for any of this.** `mesh_call` is
already generic RPC and `mesh_publish`/`mesh_watch` are already generic
pub/sub — every capability this service exposes is reachable through tools
that already ship. This repo is purely server-side: a new citizen for the
mesh, not a new client capability.
