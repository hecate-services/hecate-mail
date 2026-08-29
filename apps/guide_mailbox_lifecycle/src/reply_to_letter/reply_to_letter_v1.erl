%%% @doc Command `reply_to_letter_v1`.
%%%
%%% `citizen_did` is the REPLIER (whose mailbox holds the original
%%% letter). Deliberately does NOT take the original sender's DID as
%%% input -- the handler reads it from the original letter already in
%%% this mailbox's own state, so a replier can't misrepresent who they're
%%% replying to.
-module(reply_to_letter_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1, get_letter_id/1, get_subject/1, get_body/1]).

-record(reply_to_letter_v1, {
    citizen_did :: binary() | undefined,
    letter_id :: binary() | undefined,
    subject :: binary() | undefined,
    body :: binary() | undefined
}).

-opaque t() :: #reply_to_letter_v1{}.
-export_type([t/0]).

command_type() -> reply_to_letter_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, letter_id := Id} = M) when is_binary(Did), is_binary(Id) ->
    {ok, #reply_to_letter_v1{
        citizen_did = Did,
        letter_id = Id,
        subject = maps:get(subject, M, <<"">>),
        body = maps:get(body, M, <<"">>)
    }};
from_map(_) ->
    {error, missing_citizen_did_or_letter_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#reply_to_letter_v1{citizen_did = Did, letter_id = Id})
  when is_binary(Did), byte_size(Did) > 0, is_binary(Id), byte_size(Id) > 0 -> ok;
validate(_) -> {error, missing_citizen_did_or_letter_id}.

-spec to_map(t()) -> map().
to_map(#reply_to_letter_v1{} = Cmd) ->
    #{
        command_type => reply_to_letter_v1,
        citizen_did => Cmd#reply_to_letter_v1.citizen_did,
        letter_id => Cmd#reply_to_letter_v1.letter_id,
        subject => Cmd#reply_to_letter_v1.subject,
        body => Cmd#reply_to_letter_v1.body
    }.

-spec stream_id(t()) -> binary().
stream_id(#reply_to_letter_v1{citizen_did = Did}) ->
    mailbox_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary() | undefined.
get_citizen_did(#reply_to_letter_v1{citizen_did = V}) -> V.

-spec get_letter_id(t()) -> binary() | undefined.
get_letter_id(#reply_to_letter_v1{letter_id = V}) -> V.

-spec get_subject(t()) -> binary() | undefined.
get_subject(#reply_to_letter_v1{subject = V}) -> V.

-spec get_body(t()) -> binary() | undefined.
get_body(#reply_to_letter_v1{body = V}) -> V.
