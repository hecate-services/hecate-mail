%%% @doc Command `deposit_letter_v1`.
%%%
%%% Deposits a letter into `to_citizen_did`'s mailbox. `letter_id` is
%%% caller-supplied (or minted here if absent) rather than server-
%%% generated downstream, so a retried deposit is idempotent at the
%%% RESPONDER layer if the caller reuses the same id -- this desk itself
%%% doesn't de-duplicate (see `maybe_deposit_letter`'s own note).
-module(deposit_letter_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_letter_id/1, get_to_citizen_did/1, get_from_did/1,
         get_subject/1, get_body/1, get_reply_letter_id/1]).

-record(deposit_letter_v1, {
    letter_id :: binary() | undefined,
    to_citizen_did :: binary() | undefined,
    from_did :: binary() | undefined,
    subject :: binary() | undefined,
    body :: binary() | undefined,
    reply_letter_id :: binary() | undefined
}).

-opaque t() :: #deposit_letter_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> deposit_letter_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{to_citizen_did := To, from_did := From} = M) when is_binary(To), is_binary(From) ->
    LetterId = maps:get(letter_id, M, mint_letter_id()),
    {ok, #deposit_letter_v1{
        letter_id = LetterId,
        to_citizen_did = To,
        from_did = From,
        subject = maps:get(subject, M, <<"">>),
        body = maps:get(body, M, <<"">>),
        reply_letter_id = maps:get(reply_letter_id, M, undefined)
    }};
from_map(_) ->
    {error, missing_to_citizen_did_or_from_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#deposit_letter_v1{to_citizen_did = To, from_did = From})
  when is_binary(To), byte_size(To) > 0, is_binary(From), byte_size(From) > 0 -> ok;
validate(_) -> {error, missing_to_citizen_did_or_from_did}.

-spec to_map(t()) -> map().
to_map(#deposit_letter_v1{} = Cmd) ->
    #{
        command_type => deposit_letter_v1,
        letter_id => Cmd#deposit_letter_v1.letter_id,
        to_citizen_did => Cmd#deposit_letter_v1.to_citizen_did,
        from_did => Cmd#deposit_letter_v1.from_did,
        subject => Cmd#deposit_letter_v1.subject,
        body => Cmd#deposit_letter_v1.body,
        reply_letter_id => Cmd#deposit_letter_v1.reply_letter_id
    }.

-spec stream_id(t()) -> binary().
stream_id(#deposit_letter_v1{to_citizen_did = To}) ->
    mailbox_aggregate:stream_id(To).

-spec get_letter_id(t()) -> binary() | undefined.
get_letter_id(#deposit_letter_v1{letter_id = V}) -> V.

-spec get_to_citizen_did(t()) -> binary() | undefined.
get_to_citizen_did(#deposit_letter_v1{to_citizen_did = V}) -> V.

-spec get_from_did(t()) -> binary() | undefined.
get_from_did(#deposit_letter_v1{from_did = V}) -> V.

-spec get_subject(t()) -> binary() | undefined.
get_subject(#deposit_letter_v1{subject = V}) -> V.

-spec get_body(t()) -> binary() | undefined.
get_body(#deposit_letter_v1{body = V}) -> V.

-spec get_reply_letter_id(t()) -> binary() | undefined.
get_reply_letter_id(#deposit_letter_v1{reply_letter_id = V}) -> V.

mint_letter_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16)).
