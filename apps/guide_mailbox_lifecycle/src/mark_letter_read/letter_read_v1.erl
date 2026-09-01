%%% @doc Event `letter_read_v1`.
%%%
%%% Carries `citizen_did' explicitly -- the mailbox stream address is a
%%% one-way 128-bit digest of the DID (reckon-db's own stream-id
%%% contract requires it, see `mailbox_aggregate:stream_id/1''s doc),
%%% not the DID itself, so `letter_lifecycle_to_mailboxes' reads this
%%% field directly rather than trying to recover it from `stream_id'.
-module(letter_read_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_letter_id/1, get_citizen_did/1, get_read_at/1]).

-record(letter_read_v1, {
    letter_id :: binary(),
    citizen_did :: binary(),
    read_at :: integer()
}).

-opaque t() :: #letter_read_v1{}.
-export_type([t/0]).

event_type() -> <<"letter_read_v1">>.

-spec new(map()) -> t().
new(#{letter_id := Id, citizen_did := CitizenDid} = Params) ->
    #letter_read_v1{
        letter_id = Id,
        citizen_did = CitizenDid,
        read_at = maps:get(read_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{letter_id := Id, citizen_did := CitizenDid, read_at := At})
  when is_binary(Id), is_binary(CitizenDid), is_integer(At) ->
    {ok, #letter_read_v1{letter_id = Id, citizen_did = CitizenDid, read_at = At}};
from_map(_) ->
    {error, invalid_letter_read_event}.

-spec to_map(t()) -> map().
to_map(#letter_read_v1{letter_id = Id, citizen_did = CitizenDid, read_at = At}) ->
    #{event_type => <<"letter_read_v1">>, letter_id => Id, citizen_did => CitizenDid, read_at => At}.

-spec get_letter_id(t()) -> binary().
get_letter_id(#letter_read_v1{letter_id = V}) -> V.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#letter_read_v1{citizen_did = V}) -> V.

-spec get_read_at(t()) -> integer().
get_read_at(#letter_read_v1{read_at = V}) -> V.
