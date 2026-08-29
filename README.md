# hecate-mail

**Async mailboxes for the Macula mesh -- lets an agent delegate work to a citizen who is not online right now**

## Plan

The scaffold below builds and passes its own tests but implements no domain
logic yet. The full design -- mail-location routing, mailboxes, why identity
lives in the sibling [`hecate-citizens`](https://github.com/hecate-services/hecate-citizens)
service instead of here, the open caller-identity-verification question --
is in [`plans/PLAN_ROOT.md`](plans/PLAN_ROOT.md). Start there.

## Status: scaffold

The service boots, joins the mesh and answers `/health` on 8490. It
does nothing else yet.

It announces no capability and asks the realm for no authority, because it can do
nothing yet. Both lists grow when the thing they name exists. Advertising a
capability before it exists puts a lie on the mesh where another service can find
it and call it.

## Running it

    rebar3 compile
    rebar3 eunit
    rebar3 lint

    scripts/health.sh                      # against a running node

Building the image needs a Rust toolchain, because macula ships a QUIC NIF and
the alpine build compiles it from source rather than fetching one linked against
a different libc.

    podman build -t hecate-mail -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `HECATE_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. No default: a service that guesses its realm announces itself where nobody can attribute it. |
| `MACULA_STATION_SEEDS` | required | Station to dial. No default: naming a realm costs nothing, dialling a production station from every dev clone does. |
| `HECATE_HEALTH_PORT` | `8490` | Health endpoint. Host networking makes a collision a silent bind failure, so check the host before changing.  |
| `HECATE_NODE_NAME` | `hecate_mail` | Erlang node name. |
| `HECATE_NODE_HOST` | `127.0.0.1` | Erlang node host. |
| `HECATE_COOKIE` | `hecate_mail` | Erlang cookie. |

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry **placement**: which
host, which station, which realm, which secret store. Keeping the two apart is
what stops a config table in a README and the real environment drifting.

## Deployment

CI builds on every push to `main` and pushes
`ghcr.io/hecate-services/hecate-mail:latest` plus the semver tag. Pull `:latest` under
watchtower and a merge is a deploy, while a rollback is pinning to a semver tag.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `HECATE_REALM` supplied from somewhere it is not committed.

## The service contract

Six callbacks in `hecate_mail_service`, all required, all resolved **by name** by
`hecate_om` at startup on a live node. The `-behaviour(hecate_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

### The store

This service was scaffolded with `store=1`, so it owns a `reckon-db` store called
`hecate_mail_store`. `store_id/0` and `data_dir/0` are exported, `hecate_om:boot/1`
opens the store and its evoq subscription before `start/1` fires, and
`config/sys.config.src` carries the `evoq` adapter block that boot requires.

⚠ **The store id is written in two places**, `store_id/0` and the `evoq` block,
and nothing makes them agree by itself. A generated test compares them, along
with a second one asserting the `evoq` block is present at all. Keep both.

⚠ **`deploy/docker-compose.yml` mounts a volume, and on a node it must.** Without
it the record lives inside the container and every recreate destroys it, which is
the same as not keeping one.

The store is node-local. To make it span every node running the same `store_id`,
export the optional `store_mode/0` callback returning `cluster`, and `hecate_om`
starts it with reckon-db discovery and Ra clustering. It is not generated,
because `single` is the default and a scaffold should not decide that for you.

## Licence

Apache-2.0.
