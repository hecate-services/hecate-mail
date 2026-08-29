# PART 2 — Citizens Directory

Read-model only, no `reckon-db` event store — same shape `hecate-stations`
already proves works: `read_model_id/0` + `data_dir/0`, a `barrel_docdb`
database, populated by a Listener → Policy → Projection chain
(`hecate-om/guides/read_model_services.md`).

## Why read-model, not event-sourced

A citizen's directory entry is presence data, not a business process with a
history worth an audit trail — closer to a DHT record's shape (freshness,
republish, TTL-based expiry) than to something like an order or a mailbox
letter. Mailboxes (PART3) genuinely are a business process worth
event-sourcing; the directory isn't, and forcing it through `reckon-db`
would buy nothing over `hecate-stations`'s already-proven pattern.

## Capabilities exposed

```erlang
capabilities() ->
    [
     #{name => <<"hecate_mcp_mail.register_citizen">>, version => 1,
       handler => {register_citizen_handler, []}},
     #{name => <<"hecate_mcp_mail.list_citizens">>, version => 1,
       handler => {list_citizens_handler, []}},
     #{name => <<"hecate_mcp_mail.get_citizen">>, version => 1,
       handler => {get_citizen_handler, []}}
    ].
```

Each is directly `mesh_call`-able from `macula-mcp` with no changes there —
`mesh_call({procedure: "hecate_mcp_mail.list_citizens", args: {}})`.

## Self-registration (the local write path)

```erlang
%% register_citizen_handler.erl
-module(register_citizen_handler).
-behaviour(macula_response).
-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

handle_request(Payload, State) ->
    Did         = hecate_om_wire:field(citizen_did, Payload),
    DisplayName = hecate_om_wire:field(display_name, Payload, <<"">>),
    HostedAt    = hecate_om_wire:field(hosted_at, Payload),   %% this instance's own host:port
    Capabilities = hecate_om_wire:field(offers, Payload, []),
    ExpiresAt   = erlang:system_time(millisecond) + ?PRESENCE_TTL_MS,
    Fields = #{citizen_did => Did, display_name => DisplayName,
               hosted_at => HostedAt, offers => Capabilities,
               expires_at => ExpiresAt},
    citizens_read_model:upsert(Fields),
    ok = hecate_om_pubsub:publish(<<"hecate_mcp_mail.citizen_presence">>, Fields),
    {reply, #{ok => 1, expires_at => ExpiresAt}, State}.
```

**A citizen re-registers periodically to stay listed** (client-side
responsibility — e.g. every 5 minutes for a 20-minute TTL, the same
3-4× margin `read_model_services.md` recommends for capability
re-advertisement). No explicit "goodbye" event exists or is needed: a
citizen who stops re-registering simply ages out of the directory at
`expires_at`, on every instance, for free, via the same read-time filter
covered below.

**No booleans, business-verb naming, ID in payload not topic** — the
`hecate_mcp_mail.citizen_presence` topic name has no citizen ID in it; the
DID lives in the payload, exactly the `macula-mcp` etiquette this whole
workspace already settled on for the same reasons (topic-explosion
avoidance, wire-format constraints). `offers` (not `capabilities`, to avoid
colliding in naming with `hecate_om`'s own `capabilities/0`) is a small list
of what this citizen's agent can be asked to do, informational only in v1 —
not a capability grant, just a hint shown in `get_citizen`.

## Federation — the user's mid-plan addition, and the right pattern for it

**Multiple `hecate-mcp-mail` instances (plural, deliberately — see PART4 on
why more than one may exist) sync their directories via mesh facts, using
the exact Listener → Policy → Projection triple `read_model_services.md`
documents, not a bespoke mechanism:**

```erlang
%% hecate_mcp_mail_service.erl
subscriptions() ->
    [{<<"hecate_mcp_mail.citizen_presence">>, citizen_presence_listener, []}].
```

```erlang
%% citizen_presence_listener.erl  (Listener -- verify, hand off, nothing else)
-module(citizen_presence_listener).
-behaviour(macula_subscriber).
-export([init/1, handle_event/4]).

init(Args) -> {ok, Args}.

handle_event(_Topic, Fact, _Meta, State) ->
    on_citizen_presence_maybe_admit:handle(Fact),
    {noreply, State}.
```

```erlang
%% on_citizen_presence_maybe_admit.erl  (Policy -- pure decide/2, unit tested with zero mesh)
-module(on_citizen_presence_maybe_admit).
-export([handle/1, decide/2]).

handle(Fact) ->
    Did = maps:get(citizen_did, Fact),
    Existing = citizens_read_model:find(Did),
    case decide(Existing, maps:get(expires_at, Fact)) of
        admit -> citizens_read_model:upsert(Fact);
        stale -> ok
    end.

decide(undefined, _Incoming) -> admit;
decide(#{expires_at := Cur}, Incoming) when Incoming >= Cur -> admit;
decide(_Existing, _Incoming) -> stale.
```

```erlang
%% citizens_read_model.erl  (Projection -- dumb upsert, expiry-aware read)
upsert(Fields) ->
    barrel_docdb:put_doc(hecate_om:read_model(), storage_key(Fields), Fields).

fold(Fun, Acc) ->
    Now = erlang:system_time(millisecond),
    fold_docs(fun(Doc, A) ->
        case maps:get(expires_at, Doc, 0) > Now of
            true  -> Fun(Doc, A);
            false -> {ok, A}
        end
    end, Acc).
```

This is not new design — it is `read_model_services.md`'s own pattern,
applied to citizen presence instead of DHT node records. Whichever instance
a citizen happens to register at, every other instance running the same
subscription converges onto the same directory within one republish
interval, and a citizen who vanishes (crash, network loss, deliberate
departure — no distinction needed) ages out of *every* instance's copy on
the same schedule, because it's the same `expires_at` field driving all of
them.

`decide/2` is the one piece of decision logic and is fully unit-testable
with zero mesh, per `mesh_native_services.md`'s own testing convention:

```erlang
admits_a_never_seen_citizen_test() ->
    ?assertEqual(admit, on_citizen_presence_maybe_admit:decide(undefined, 12345)).
admits_a_fresher_reregistration_test() ->
    ?assertEqual(admit, on_citizen_presence_maybe_admit:decide(#{expires_at => 100}, 200)).
drops_a_late_stale_delivery_test() ->
    ?assertEqual(stale, on_citizen_presence_maybe_admit:decide(#{expires_at => 200}, 100)).
```

## What `hosted_at` is for, and why it's the field that matters most

Every directory entry carries `hosted_at` — the `host:port` of the
`hecate-mcp-mail` *instance* the citizen actually registered at (not a
station address, an instance address). This is what makes PART3's "letters
don't federate" decision workable: to deposit a letter for citizen X, an
agent first calls `get_citizen` (on whichever instance is convenient — the
directory is the same everywhere) to learn X's `hosted_at`, then calls
`deposit_letter` on *that specific instance* directly (`mesh_call`'s
existing `host` parameter). The letter is created exactly once, on exactly
the instance that will serve it back later. No instance needs to guess where
someone's mail "really" lives, because the directory already told it.

## Multiple citizens directory entries per DID?

No — `citizen_did` is the upsert key. A citizen who registers at two
different instances (or re-registers with a new `hosted_at`, e.g. their
preferred instance changed) simply overwrites their own single entry
everywhere it propagates, keyed on the same field the Policy already checks
freshness against. There is deliberately no "citizen belongs to exactly one
instance forever" constraint — the freshest `hosted_at` wins, exactly like
the freshest `expires_at` wins.

## Explicitly not in v1

- **No search/filter beyond exact-DID lookup and full listing.** `list_citizens`
  returns everything unexpired; pagination/filtering is a v2 concern once a
  directory is large enough to need it (i.e., once this is actually a
  problem, not speculatively).
- **No reputation, no vouching, no "verified citizen" badge.** `identity_model.md`'s
  own roadmap has a v2 UCAN/policy layer coming for services generally; the
  directory doesn't try to get ahead of it.
- **No de-duplication of "the same human across two DIDs."** A DID is a
  citizen for this service's purposes, full stop.
