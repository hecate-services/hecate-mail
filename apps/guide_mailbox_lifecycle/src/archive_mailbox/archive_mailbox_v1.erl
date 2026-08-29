%%% @doc Command `archive_mailbox_v1'.
%%%
%%% The death of a mailbox aggregate -- terminal unless later reversed by
%%% `unarchive_mailbox', mirroring hecate-whiteboard's `archive_board'.
%%% @end
-module(archive_mailbox_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(archive_mailbox_v1, {
    citizen_did :: binary() | undefined
}).

-opaque t() :: #archive_mailbox_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> archive_mailbox_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #archive_mailbox_v1{citizen_did = Did}};
new(_) ->
    {error, missing_citizen_did}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #archive_mailbox_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#archive_mailbox_v1{citizen_did = Did}) when is_binary(Did), byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#archive_mailbox_v1{citizen_did = Did}) ->
    #{command_type => archive_mailbox_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#archive_mailbox_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#archive_mailbox_v1{citizen_did = V}) -> V.
