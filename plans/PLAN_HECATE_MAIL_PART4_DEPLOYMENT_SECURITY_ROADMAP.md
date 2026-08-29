# PART 4 — Deployment, Security, Roadmap

## This cannot run on a user's laptop — and that's a correction, not a style choice

Earlier in the conversation that produced this repo, the suggestion was "run
it as a private single-instance build on your own machine first." Reading
`hecate_om/guides/identity_model.md` in full before writing this plan
surfaced that this was wrong, not just informal:

> "No user-bound services. A `hecate-rag` running on Alice's laptop 'for
> Alice' is wrong. Move it onto a realm-owned infrastructure node and let
> Alice consult it across the mesh."
>
> "A Hecate service is one OTP release and one OCI container, running on an
> infrastructure node rather than on a user's laptop. A laptop is a citizen:
> it consults services across the mesh, it does not host them."

So `hecate-mail` needs a real deployment target from day one — a
realm-provisioned service principal, on infrastructure the realm owns (per
this workspace's own deployment conventions: `beam00-03`, docker +
watchtower; or `msi00`, podman + Quadlet). This doesn't block *development*
(the scaffold builds and its tests pass on a laptop right now, as verified
while writing this plan), but it does mean "ship it" means "provision it
properly," not "leave a process running in a terminal."

## Provisioning — corrected against real fleet practice, 2026-08-29

**LIVE as of this writing**, on `beam01.lab` and `beam02.lab`, healthy,
answering `/health` on 8496. This section originally described the formal
realm service-principal cert flow (`identity_spec/0` →
`/api/v1/services/provision` → cert mounted at
`/etc/hecate/secrets/hecate-mail/`) as a hard prerequisite, reasoning from
`identity_model.md`'s own description. **That turned out not to match what
any currently-deployed service on this fleet actually does** — checked
directly against five real, running examples (`hecate-tube`,
`hecate-whiteboard`, `hecate-biotope`, `hecate-turn-credentials`,
`hecate-stations`) before deploying this one, not assumed. None of them
mount a service-principal cert. Every one boots with exactly two identity-
related environment variables:

- `HECATE_REALM` — a 64-hex realm tag, shared across services that need to
  find each other (this deployment reuses the same tag `hecate-tube` and
  `hecate-whiteboard` already hold on `beam01`/`beam02`, derived
  node-to-node rather than minted fresh — see below).
- `MACULA_STATION_SEEDS` — which station(s) to dial.

The formal cert-provisioning flow `identity_model.md` describes may be a
real v1 mechanism for services that need it, but it is not something
`hecate_om:boot/1` requires to run today, and no sibling service pays that
cost. **Corrected here rather than left wrong**, since the plan is meant to
describe what actually ships.

## Real deployment, as executed

1. **Infrastructure lives in `macula-io/macula-demo`** (private repo), NOT
   in this repo. Per-node config: `infrastructure/beamXX.lab/
   hecate-mail-config.env` (committed, key-free — station seed only).
   Shared compose: `infrastructure/scripts/docker-compose.hecate-mail.yml`.
   Both follow `hecate-whiteboard`'s and `hecate-biotope`'s own committed
   pattern exactly — no new deployment mechanism invented for this repo.
2. **Secret**: `~/.hecate/secrets/hecate-mail.env` (0600, `HECATE_REALM`
   only) on each node, seeded via `scripts/enroll-hecate-mail-secret.sh`
   — derived from that same node's already-seeded `hecate-whiteboard.env`
   for the first node, then node-to-node for the second. The value never
   transits the operator's own workstation as anything but an SSH-to-SSH
   pipe.
3. **Rollout is pull-based, not pushed.** Each beam node runs a
   `hecate-reconcile` systemd `--user` timer (every 2 minutes) that
   `git pull --ff-only`s `macula-demo` and applies whatever
   `infrastructure/<node>/reconcile.manifest` lists. Adding this service
   meant appending one line + a dated comment block to each of
   `beam01.lab/reconcile.manifest` and `beam02.lab/reconcile.manifest`,
   committing, and pushing — the box does the rest on its own schedule
   (or immediately, via `systemctl --user start hecate-reconcile.service`
   by hand, which is how this was actually verified same-session rather
   than waiting up to 2 minutes).
4. **Port 8496** — the next free slot on this fleet's own ledger, checked
   directly (`grep -rhoE '84[0-9]{2}'` across the infra repo) rather than
   guessed: 8490/8491 `hecate-tube`, 8492/8493 `hecate-whiteboard`, 8494
   `hecate-turn-credentials`, 8495 `hecate-stations`. Host networking
   makes a collision a silent bind failure, not an error, so this was
   worth checking before deploying, not after.
5. **Stations**: reused `hecate-whiteboard`'s own already-vetted distinct
   pair (`station-de-falkenstein` on beam01, `station-fi-helsinki` on
   beam02, confirmed via `dig AAAA` to be genuinely different boxes) rather
   than re-deriving that check for a second service on the same two nodes.

Watchtower (`com.centurylinklabs.watchtower.enable=true` label, already in
the compose file) handles image updates from here — a future `git push` to
this repo's `main` rebuilds `ghcr.io/hecate-services/hecate-mail:latest`,
and both nodes pick it up on their own without any further manual step.

## Why more than one instance might genuinely exist

PART2's federation design isn't there for redundancy theater — a second (or
third) instance, run by a different party, is what actually makes "the
directory" mean something beyond "whoever happens to run the one copy." A
cooperative-contributed node (per `identity_model.md`'s own "first
non-Tienen service node" framing) running its own `hecate-mail` and
federating with the original is the natural shape once this is proven —
each instance is still a properly-provisioned institution, none of them a
citizen's laptop; federation is between institutions, not a workaround for
skipping provisioning.

## Security considerations, stated plainly

- **The realm boundary is real, but coarse.** It proves "you're a
  legitimate participant," not "you're allowed to do this specific thing to
  this specific mailbox." PART3's open question about caller-identity
  verification is the sharp edge of this — resolve it before `get_mailbox`
  ships, not after.
- **Directory entries are self-asserted.** Nothing stops a citizen from
  registering a misleading `display_name` or `offers` list — v1 treats the
  directory as a phone book, not a background check. A caller deciding
  whether to trust what a listed citizen's agent does with a deposited
  letter is exactly the same trust decision as trusting any stranger's
  output today; this service delivers letters, it does not vouch for them
  (the same framing already settled in the conversation that produced this
  repo).
- **No rate limiting or spam control in v1.** `deposit_letter` being callable
  by any realm citizen means a misbehaving citizen could flood another's
  mailbox. Deferred deliberately (see Phase 2 below), not overlooked — build
  it once real usage shows whether it's actually needed, and what shape of
  abuse actually shows up, rather than guessing now.
- **No content moderation.** Out of scope for this service entirely; if it's
  ever needed, it belongs at the citizen/client side (a recipient's own
  agent deciding what to act on), consistent with the "postoffice delivers,
  doesn't vouch" framing throughout this plan.

## Phased build order

**Phase 0 — `hecate-citizens` ships first.** This repo's `register_mailbox`
is meaningless without a citizen to register on behalf of, and the
original "show me other macula citizens" ask is actually answered by
`hecate-citizens`'s `list_citizens`, not by anything in this repo. Build
and deploy that service before Phase 1 here.

**Phase 1 — Mail-location directory.**
`register_mailbox` / `get_citizen_mail_location`, the Listener/Policy/
Projection federation chain, `test_live/` coverage of a real register →
lookup round trip against the demo fleet.

**Phase 2 — Mailboxes, write side first.**
`deposit_letter` end to end (CMD → event → PRJ), because it's safe to ship
without the authorization question resolved (no read path exists yet to get
wrong). Resolve PART3's caller-identity question in parallel — it blocks
Phase 3, not this phase.

**Phase 3 — Mailboxes, read side.**
`get_mailbox` / `get_letter`, gated behind whichever fix PART3's open
question resolves to. `reply_to_letter` and `archive_letter` land here too,
since they're only useful once a citizen can actually see their mail.

**Phase 4 — Hardening, only once Phases 1–3 have real usage to learn from.**
Rate limiting, and a periodic `barrel_docdb` purge of long-expired
mail-location entries (a size optimization per `read_model_services.md`'s
own note that this is "not a correctness requirement" — the read-time TTL
filter already makes staleness correct with zero purge).

## Explicitly out of scope for this repo, permanently, not just "for now"

- Building `hecate-mcp-agora` (separate plan, separate repo, when started).
- Any change to `macula-mcp` — this repo requires none.
- A reputation/trust-scoring system beyond `identity_model.md`'s own v2
  UCAN roadmap for services generally.
- A UI. This is an MCP-and-mesh-facing service; any human-facing view of a
  mailbox is a client's concern, not this repo's.
