%%% @doc Event `mailbox_unarchived_v1'.
-module(mailbox_unarchived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_unarchived_at/1]).

-record(mailbox_unarchived_v1, {
    citizen_did :: binary(),
    unarchived_at :: integer()
}).

-opaque t() :: #mailbox_unarchived_v1{}.
-export_type([t/0]).

event_type() -> <<"mailbox_unarchived_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #mailbox_unarchived_v1{
        citizen_did = Did,
        unarchived_at = maps:get(unarchived_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, unarchived_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #mailbox_unarchived_v1{citizen_did = Did, unarchived_at = At}};
from_map(_) ->
    {error, invalid_mailbox_unarchived_event}.

-spec to_map(t()) -> map().
to_map(#mailbox_unarchived_v1{citizen_did = Did, unarchived_at = At}) ->
    #{event_type => <<"mailbox_unarchived_v1">>, citizen_did => Did, unarchived_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#mailbox_unarchived_v1{citizen_did = V}) -> V.

-spec get_unarchived_at(t()) -> integer().
get_unarchived_at(#mailbox_unarchived_v1{unarchived_at = V}) -> V.
