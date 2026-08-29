%%% @doc Event `mailbox_initiated_v1'.
-module(mailbox_initiated_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_initiated_at/1]).

-record(mailbox_initiated_v1, {
    citizen_did :: binary(),
    initiated_at :: integer()
}).

-opaque t() :: #mailbox_initiated_v1{}.
-export_type([t/0]).

event_type() -> <<"mailbox_initiated_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #mailbox_initiated_v1{
        citizen_did = Did,
        initiated_at = maps:get(initiated_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, initiated_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #mailbox_initiated_v1{citizen_did = Did, initiated_at = At}};
from_map(_) ->
    {error, invalid_mailbox_initiated_event}.

-spec to_map(t()) -> map().
to_map(#mailbox_initiated_v1{citizen_did = Did, initiated_at = At}) ->
    #{event_type => <<"mailbox_initiated_v1">>, citizen_did => Did, initiated_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#mailbox_initiated_v1{citizen_did = V}) -> V.

-spec get_initiated_at(t()) -> integer().
get_initiated_at(#mailbox_initiated_v1{initiated_at = V}) -> V.
