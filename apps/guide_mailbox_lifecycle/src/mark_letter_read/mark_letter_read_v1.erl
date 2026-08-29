%%% @doc Command `mark_letter_read_v1`.
-module(mark_letter_read_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1, get_letter_id/1]).

-record(mark_letter_read_v1, {
    citizen_did :: binary() | undefined,
    letter_id :: binary() | undefined
}).

-opaque t() :: #mark_letter_read_v1{}.
-export_type([t/0]).

command_type() -> mark_letter_read_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, letter_id := Id}) when is_binary(Did), is_binary(Id) ->
    {ok, #mark_letter_read_v1{citizen_did = Did, letter_id = Id}};
from_map(_) ->
    {error, missing_citizen_did_or_letter_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#mark_letter_read_v1{citizen_did = Did, letter_id = Id})
  when is_binary(Did), byte_size(Did) > 0, is_binary(Id), byte_size(Id) > 0 -> ok;
validate(_) -> {error, missing_citizen_did_or_letter_id}.

-spec to_map(t()) -> map().
to_map(#mark_letter_read_v1{citizen_did = Did, letter_id = Id}) ->
    #{command_type => mark_letter_read_v1, citizen_did => Did, letter_id => Id}.

-spec stream_id(t()) -> binary().
stream_id(#mark_letter_read_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#mark_letter_read_v1{citizen_did = V}) -> V.

-spec get_letter_id(t()) -> binary() | undefined.
get_letter_id(#mark_letter_read_v1{letter_id = V}) -> V.
