# PART 2 — Citizens Directory (revised: extracted to `hecate-citizens`)

**Superseded design note, kept for history:** this part originally specified
a full citizens directory (identity + `hosted_at` routing) owned directly by
this service. That changed the moment `hecate-mcp-agora` was named as a real
next service needing the same identity data — see
[`hecate-services/hecate-citizens`](https://github.com/hecate-services/hecate-citizens)'s
own `plans/PLAN_ROOT.md` for the full reasoning and design. This part now
covers only what stays in `hecate-mcp-mail`.

## What moved out, and why

Identity (`citizen_did`, `display_name`, `offers`, generic presence) now
lives in `hecate-citizens`, federated across instances via mesh facts using
the Listener/Policy/Projection pattern. Any service — this one, `agora`,
whatever comes after — depends on it for "does this DID belong to a known
citizen," rather than each maintaining its own copy that can silently
diverge from the others.

## What stays here — mailbox routing, not identity

`hecate-mcp-mail` still needs to answer one question `hecate-citizens`
deliberately doesn't: **which `hecate-mcp-mail` instance holds this
citizen's mailbox?** That's mail-specific routing data, not identity, per
`hecate-citizens`'s own scope test ("would a second, unrelated consumer
plausibly want this same fact?" — no other service cares where someone's
mail lives). So this service keeps its own thin directory, same mechanism,
narrower content:

```erlang
#{citizen_did => Did,          % which citizen -- looked up in hecate-citizens if display info is needed, not duplicated here
  hosted_at   => HostedAt,     % this mail instance's own host:port
  expires_at  => ExpiresAt}    % same TTL/staleness mechanism as before
```

No `display_name`, no `offers` — those are `hecate-citizens`'s job now. If
a caller wants a citizen's display name alongside their mail-hosting
location, that's two calls (`hecate_citizens.get_citizen` +
`hecate_mcp_mail.get_citizen_mail_location`), not one merged record — cheap,
and it keeps the services genuinely decoupled rather than secretly coupled
through a shared schema.

## Capabilities exposed

```erlang
capabilities() ->
    [
     #{name => <<"hecate_mcp_mail.register_mailbox">>, version => 1,
       handler => {register_mailbox_handler, []}},
     #{name => <<"hecate_mcp_mail.get_citizen_mail_location">>, version => 1,
       handler => {get_citizen_mail_location_handler, []}}
    ].
```

Renamed from `register_citizen`/`get_citizen`/`list_citizens` to make the
narrowed scope obvious from the name alone — this is registering *for
mail*, not registering as a citizen (that's `hecate_citizens.register_presence`
now). **No `list_citizens` equivalent here** — "list everyone with a
mailbox" was never a distinct need from "list everyone" once identity moved
out; `hecate_citizens.list_citizens` covers it, and a caller checks
`get_citizen_mail_location` only for a specific DID they already intend to
mail.

## Registration flow (two independent calls, composed by the citizen's own agent)

```erlang
%% register_mailbox_handler.erl
-module(register_mailbox_handler).
-behaviour(macula_response).
-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

handle_request(Payload, State) ->
    Did       = hecate_om_wire:field(citizen_did, Payload),
    HostedAt  = hecate_om_wire:field(hosted_at, Payload),
    ExpiresAt = erlang:system_time(millisecond) + ?MAIL_LOCATION_TTL_MS,
    Fields = #{citizen_did => Did, hosted_at => HostedAt, expires_at => ExpiresAt},
    mail_location_read_model:upsert(Fields),
    ok = hecate_om_pubsub:publish(<<"hecate_mcp_mail.mail_location">>, Fields),
    {reply, #{ok => 1, expires_at => ExpiresAt}, State}.
```

A citizen registers with `hecate-citizens` (identity) and, separately, with
`hecate-mcp-mail` (a mailbox) if they want one — **this service does not
call `hecate-citizens` on a citizen's behalf to write anything.** The two
services are not chained for writes, only optionally consulted for reads
(and even that's a nice-to-have — nothing here blocks on `hecate-citizens`
being reachable; a `deposit_letter` addressed to an unrecognized-by-citizens
DID still succeeds, since mail addresses by DID, not by "verified citizen"
status).

## Federation — same pattern, narrower topic, unchanged from the original design

```erlang
%% hecate_mcp_mail_service.erl
subscriptions() ->
    [{<<"hecate_mcp_mail.mail_location">>, mail_location_listener, []}].
```

Listener → Policy (`on_mail_location_maybe_admit:decide/2`, identical
admit/stale-by-`expires_at` shape as before, just renamed) → Projection
(`mail_location_read_model:upsert/1`). Nothing about the federation
mechanism itself changed — only what's being federated (routing, not
identity) and its name.

## What `hosted_at` is for — unchanged in purpose, narrower in company

To deposit a letter for citizen X, an agent calls
`hecate_mcp_mail.get_citizen_mail_location` (on whichever
`hecate-mcp-mail` instance is convenient — the mail-location directory is
the same everywhere, same as before) to learn X's `hosted_at`, then calls
`deposit_letter` on *that specific instance* directly (`mesh_call`'s `host`
parameter). Unchanged from the original design; only the field's neighbors
changed.

## Explicitly not in v1

- **No merged citizen+mail-location view served by this service.** A caller
  wanting both makes two calls, to two services. Resist the temptation to
  add a convenience endpoint that re-couples what was just decoupled.
- Everything PART2's original "explicitly not in v1" list already said
  (no search/filter beyond exact lookup, no reputation) still applies,
  scoped down to mail-location data specifically.
