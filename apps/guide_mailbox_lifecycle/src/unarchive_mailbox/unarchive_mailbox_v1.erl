%%% @doc Command `unarchive_mailbox_v1'.
%%%
%%% The rebirth end of the mailbox lifecycle, mirroring
%%% hecate-whiteboard's `unarchive_board'. Clears the ARCHIVED bit; does
%%% NOT re-open the mailbox on its own -- `open_mailbox' is a separate,
%%% explicit step afterward, same as it is after `initiate_mailbox'.
%%% @end
-module(unarchive_mailbox_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(unarchive_mailbox_v1, {
    citizen_did :: binary() | undefined
}).

-opaque t() :: #unarchive_mailbox_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> unarchive_mailbox_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #unarchive_mailbox_v1{citizen_did = Did}};
new(_) ->
    {error, missing_citizen_did}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #unarchive_mailbox_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#unarchive_mailbox_v1{citizen_did = Did}) when is_binary(Did), byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#unarchive_mailbox_v1{citizen_did = Did}) ->
    #{command_type => unarchive_mailbox_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#unarchive_mailbox_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#unarchive_mailbox_v1{citizen_did = V}) -> V.
