%%% @doc Event `mailbox_closed_v1`.
-module(mailbox_closed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_closed_at/1]).

-record(mailbox_closed_v1, {
    citizen_did :: binary(),
    closed_at :: integer()
}).

-opaque t() :: #mailbox_closed_v1{}.
-export_type([t/0]).

event_type() -> <<"mailbox_closed_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #mailbox_closed_v1{
        citizen_did = Did,
        closed_at = maps:get(closed_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, closed_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #mailbox_closed_v1{citizen_did = Did, closed_at = At}};
from_map(_) ->
    {error, invalid_mailbox_closed_event}.

-spec to_map(t()) -> map().
to_map(#mailbox_closed_v1{citizen_did = Did, closed_at = At}) ->
    #{event_type => <<"mailbox_closed_v1">>, citizen_did => Did, closed_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#mailbox_closed_v1{citizen_did = V}) -> V.

-spec get_closed_at(t()) -> integer().
get_closed_at(#mailbox_closed_v1{closed_at = V}) -> V.
