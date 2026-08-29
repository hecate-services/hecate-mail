%%% @doc Command `close_mailbox_v1`.
-module(close_mailbox_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(close_mailbox_v1, {
    citizen_did :: binary() | undefined
}).

-opaque t() :: #close_mailbox_v1{}.
-export_type([t/0]).

command_type() -> close_mailbox_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #close_mailbox_v1{citizen_did = Did}};
new(_) ->
    {error, missing_citizen_did}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #close_mailbox_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#close_mailbox_v1{citizen_did = Did}) when is_binary(Did), byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#close_mailbox_v1{citizen_did = Did}) ->
    #{command_type => close_mailbox_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#close_mailbox_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#close_mailbox_v1{citizen_did = V}) -> V.
