%%% @doc The letter read model every QRY desk reads through directly --
%%% `project_mailboxes' writes here, `query_mailboxes' reads here,
%%% neither ever touches `barrel_docdb' any other way. One document per
%%% letter, keyed by `{citizen_did, letter_id}' (PART3), stored in the
%%% database `hecate_mail_service:read_model_id/0' names.
%%%
%%% Booleans (`read'/`archived') are plain Erlang terms here -- this is
%%% internal storage, not a mesh wire payload, so the org's "no bool on
%%% the wire" rule doesn't apply; `query_mailboxes' responders convert
%%% to `0'/`1' at the RPC boundary.
%%% @end
-module(mailboxes_read_model).

-export([upsert_deposited/2, mark_read/2, mark_replied/2, mark_archived/2]).
-export([find/2, list_unarchived/1, to_wire/1]).

-spec upsert_deposited(binary(), map()) -> ok.
upsert_deposited(CitizenDid, #{letter_id := LetterId} = Fields)
  when is_binary(CitizenDid), is_binary(LetterId) ->
    Doc = #{
        <<"id">> => doc_id(CitizenDid, LetterId),
        <<"citizen_did">> => CitizenDid,
        <<"letter_id">> => LetterId,
        <<"from_did">> => maps:get(from_did, Fields),
        <<"subject">> => maps:get(subject, Fields, <<"">>),
        <<"body">> => maps:get(body, Fields, <<"">>),
        <<"reply_letter_id">> => maps:get(reply_letter_id, Fields, undefined),
        <<"deposited_at">> => maps:get(deposited_at, Fields),
        <<"read">> => false,
        <<"replied">> => false,
        <<"archived">> => false
    },
    put(Doc).

-spec mark_read(binary(), binary()) -> ok.
mark_read(CitizenDid, LetterId) -> flagged(CitizenDid, LetterId, <<"read">>).

-spec mark_replied(binary(), binary()) -> ok.
mark_replied(CitizenDid, LetterId) -> flagged(CitizenDid, LetterId, <<"replied">>).

-spec mark_archived(binary(), binary()) -> ok.
mark_archived(CitizenDid, LetterId) -> flagged(CitizenDid, LetterId, <<"archived">>).

flagged(CitizenDid, LetterId, Flag) ->
    set_flag(get_doc(doc_id(CitizenDid, LetterId)), Flag).

set_flag({ok, Doc}, Flag) -> put(Doc#{Flag => true});
set_flag({error, not_found}, _Flag) -> ok.

-spec find(binary(), binary()) -> {ok, map()} | {error, not_found}.
find(CitizenDid, LetterId) ->
    get_doc(doc_id(CitizenDid, LetterId)).

%% @doc Every unarchived letter for a citizen, unread first, then
%% newest deposited_at first. A per-citizen fold over the whole
%% database (no secondary index) -- correct and simple at this
%% service's current scale; revisit with a barrel_docdb index only
%% if a real citizen's mailbox ever makes this fold slow.
-spec list_unarchived(binary()) -> [map()].
list_unarchived(CitizenDid) ->
    {ok, DbName} = hecate_om:read_model(),
    {ok, Rows} = barrel_docdb:fold_docs(DbName, fun(Doc, Acc) -> collect(CitizenDid, Doc, Acc) end, []),
    lists:sort(fun newer_unread_first/2, Rows).

collect(CitizenDid, #{<<"citizen_did">> := CitizenDid, <<"archived">> := false} = Doc, Acc) ->
    {ok, [Doc | Acc]};
collect(_CitizenDid, _Doc, Acc) ->
    {ok, Acc}.

newer_unread_first(#{<<"read">> := ReadA, <<"deposited_at">> := AtA},
                   #{<<"read">> := ReadB, <<"deposited_at">> := AtB}) ->
    rank(ReadA, AtA) =< rank(ReadB, AtB).

rank(false, At) -> {0, -At};
rank(true, At) -> {1, -At}.

%% @doc A stored doc, shaped for an RPC reply -- `undefined' fields
%% omitted (`maybe_put' convention, `station_read_model'), booleans as
%% `0'/`1' (this org's "no bool on the wire" rule -- internal storage
%% above stays plain Erlang terms, only the wire boundary converts).
-spec to_wire(map()) -> map().
to_wire(Doc) ->
    omit_undefined(#{
        letter_id => maps:get(<<"letter_id">>, Doc),
        from_did => maps:get(<<"from_did">>, Doc),
        subject => maps:get(<<"subject">>, Doc),
        body => maps:get(<<"body">>, Doc),
        reply_letter_id => maps:get(<<"reply_letter_id">>, Doc, undefined),
        deposited_at => maps:get(<<"deposited_at">>, Doc),
        read => bit(maps:get(<<"read">>, Doc)),
        replied => bit(maps:get(<<"replied">>, Doc)),
        archived => bit(maps:get(<<"archived">>, Doc))
    }).

bit(true) -> 1;
bit(false) -> 0.

omit_undefined(Map) ->
    maps:filter(fun(_K, V) -> V =/= undefined end, Map).

doc_id(CitizenDid, LetterId) ->
    <<(binary:encode_hex(CitizenDid, lowercase))/binary, ":", LetterId/binary>>.

get_doc(Id) ->
    {ok, DbName} = hecate_om:read_model(),
    barrel_docdb:get_doc(DbName, Id).

put(Doc) ->
    {ok, DbName} = hecate_om:read_model(),
    {ok, _} = barrel_docdb:put_doc(DbName, Doc),
    ok.
