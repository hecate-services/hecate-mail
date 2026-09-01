%%% @doc Projection: letter_deposited_v1 / letter_read_v1 /
%%% letter_replied_v1 / letter_archived_v1 -> the `mailboxes_read_model'
%%% barrel_docdb read model.
%%%
%%% The `evoq_read_model' handle is a checkpoint passthrough only --
%%% real data lives in `mailboxes_read_model' (barrel_docdb), not in the
%%% read model itself, matching `project_tube's channel_lifecycle_to_channels
%%% and its own cited precedent (hecate-mpong-bot).
%%%
%%% Each event carries its own owning `citizen_did' (`to_citizen_did'
%%% on `letter_deposited_v1', `citizen_did' on the other three) --
%%% NOT derived from `stream_id'. `stream_id' is a one-way 128-bit
%%% digest of the DID (reckon-db's own stream-id contract requires it,
%%% see `mailbox_aggregate:stream_id/1''s doc), so nothing could
%%% recover the DID from it even if this wanted to.
-module(letter_lifecycle_to_mailboxes).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"letter_deposited_v1">>, <<"letter_read_v1">>,
     <<"letter_replied_v1">>, <<"letter_archived_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets,
                                   #{name => mailboxes_projection}),
    {ok, #{}, RM}.

%% `Event' here is what evoq_store_subscription:evoq_event_to_routable/1
%% builds: #{event_type, event_id, stream_id, version, data, tags,
%% timestamp, epoch_us} -- the event's own fields are nested under
%% `data'. `field/2' is atom-or-binary tolerant since a round trip
%% through the store is not guaranteed to preserve atom keys.
project(#{event_type := <<"letter_deposited_v1">>, data := Data}, _Meta, State, RM) ->
    CitizenDid = field(to_citizen_did, Data),
    Fields = #{
        letter_id => field(letter_id, Data),
        from_did => field(from_did, Data),
        subject => field(subject, Data),
        body => field(body, Data),
        reply_letter_id => field(reply_letter_id, Data),
        deposited_at => field(deposited_at, Data)
    },
    ok = mailboxes_read_model:upsert_deposited(CitizenDid, Fields),
    {ok, State, RM};

project(#{event_type := <<"letter_read_v1">>, data := Data}, _Meta, State, RM) ->
    ok = mailboxes_read_model:mark_read(field(citizen_did, Data), field(letter_id, Data)),
    {ok, State, RM};

project(#{event_type := <<"letter_replied_v1">>, data := Data}, _Meta, State, RM) ->
    ok = mailboxes_read_model:mark_replied(field(citizen_did, Data), field(letter_id, Data)),
    {ok, State, RM};

project(#{event_type := <<"letter_archived_v1">>, data := Data}, _Meta, State, RM) ->
    ok = mailboxes_read_model:mark_archived(field(citizen_did, Data), field(letter_id, Data)),
    {ok, State, RM};

project(_Event, _Meta, State, RM) ->
    {skip, State, RM}.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
