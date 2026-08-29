%%% @doc Command `open_mailbox_v1`.
%%%
%%% A citizen opens (or re-opens, after closing) a mailbox on this
%%% instance. Citizen-agnostic on purpose: this desk doesn't know or care
%%% whether the citizen is human, agent, or service (see
%%% hecate-citizens' own `citizen_kind` for that) -- it only needs a DID
%%% to key the mailbox stream.
%%% @end
-module(open_mailbox_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(open_mailbox_v1, {
    citizen_did :: binary() | undefined
}).

-opaque t() :: #open_mailbox_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> open_mailbox_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #open_mailbox_v1{citizen_did = Did}};
new(_) ->
    {error, missing_citizen_did}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #open_mailbox_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#open_mailbox_v1{citizen_did = Did}) when is_binary(Did), byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#open_mailbox_v1{citizen_did = Did}) ->
    #{command_type => open_mailbox_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#open_mailbox_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#open_mailbox_v1{citizen_did = V}) -> V.
