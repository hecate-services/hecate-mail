%%% @doc Event `mailbox_archived_v1'.
-module(mailbox_archived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_archived_at/1]).

-record(mailbox_archived_v1, {
    citizen_did :: binary(),
    archived_at :: integer()
}).

-opaque t() :: #mailbox_archived_v1{}.
-export_type([t/0]).

event_type() -> <<"mailbox_archived_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #mailbox_archived_v1{
        citizen_did = Did,
        archived_at = maps:get(archived_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, archived_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #mailbox_archived_v1{citizen_did = Did, archived_at = At}};
from_map(_) ->
    {error, invalid_mailbox_archived_event}.

-spec to_map(t()) -> map().
to_map(#mailbox_archived_v1{citizen_did = Did, archived_at = At}) ->
    #{event_type => <<"mailbox_archived_v1">>, citizen_did => Did, archived_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#mailbox_archived_v1{citizen_did = V}) -> V.

-spec get_archived_at(t()) -> integer().
get_archived_at(#mailbox_archived_v1{archived_at = V}) -> V.
