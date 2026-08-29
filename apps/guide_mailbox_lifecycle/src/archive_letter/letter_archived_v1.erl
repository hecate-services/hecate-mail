%%% @doc Event `letter_archived_v1`.
-module(letter_archived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_letter_id/1, get_archived_at/1]).

-record(letter_archived_v1, {
    letter_id :: binary(),
    archived_at :: integer()
}).

-opaque t() :: #letter_archived_v1{}.
-export_type([t/0]).

event_type() -> <<"letter_archived_v1">>.

-spec new(map()) -> t().
new(#{letter_id := Id} = Params) ->
    #letter_archived_v1{
        letter_id = Id,
        archived_at = maps:get(archived_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{letter_id := Id, archived_at := At}) when is_binary(Id), is_integer(At) ->
    {ok, #letter_archived_v1{letter_id = Id, archived_at = At}};
from_map(_) ->
    {error, invalid_letter_archived_event}.

-spec to_map(t()) -> map().
to_map(#letter_archived_v1{letter_id = Id, archived_at = At}) ->
    #{event_type => <<"letter_archived_v1">>, letter_id => Id, archived_at => At}.

-spec get_letter_id(t()) -> binary().
get_letter_id(#letter_archived_v1{letter_id = V}) -> V.

-spec get_archived_at(t()) -> integer().
get_archived_at(#letter_archived_v1{archived_at = V}) -> V.
