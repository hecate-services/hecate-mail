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

## Provisioning (v1, per `identity_model.md`'s own table)

1. Register a service principal with `hecate-realm`, declaring
   `identity_spec/0`:
   ```erlang
   identity_spec() ->
       #{scope => <<"hecate-mail">>,
         actions => [<<"register_mailbox">>, <<"get_citizen_mail_location">>,
                     <<"deposit_letter">>, <<"get_mailbox">>, <<"get_letter">>],
         resources => [<<"mail_locations/*">>, <<"mailboxes/*">>],
         ttl_days => 365}.
   ```
   Ask for exactly what's advertised, per this workspace's own stated
   reasoning for that field: a popped credential should grant exactly this
   and nothing more.
2. Credential lands at `/etc/hecate/secrets/hecate-mail/`, mounted into
   the container — the same `hecate_realm_session:provision_from_inherited_creds/2`
   path every other headless service uses (v1: manual/scripted; v2, per
   `identity_model.md`'s own roadmap, the `/api/v1/services/provision`
   endpoint once policy+UCAN delegation lands — this repo doesn't build v2,
   it just isn't surprised when the credential type under it changes, since
   `hecate_om_identity` abstracts the swap).
3. Deploy via this repo's generated `Containerfile` + `deploy/docker-compose.yml`
   (already scaffolded), following whichever of this workspace's two current
   deployment paths the operator picks (docker+watchtower on the beam
   fleet, or podman+Quadlet on msi00) — same CI-builds-image,
   registry-serves-it, auto-update-rolls-it shape every other service here
   already uses. No new deployment mechanism invented for this repo.

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
