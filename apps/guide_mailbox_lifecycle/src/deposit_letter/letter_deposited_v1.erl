%%% @doc Event `letter_deposited_v1`.
-module(letter_deposited_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_letter_id/1, get_from_did/1, get_subject/1, get_body/1,
         get_reply_letter_id/1, get_deposited_at/1]).

-record(letter_deposited_v1, {
    letter_id :: binary(),
    from_did :: binary(),
    subject :: binary(),
    body :: binary(),
    reply_letter_id :: binary() | undefined,
    deposited_at :: integer()
}).

-opaque t() :: #letter_deposited_v1{}.
-export_type([t/0]).

event_type() -> <<"letter_deposited_v1">>.

-spec new(map()) -> t().
new(#{letter_id := Id, from_did := From} = Params) ->
    #letter_deposited_v1{
        letter_id = Id,
        from_did = From,
        subject = maps:get(subject, Params, <<"">>),
        body = maps:get(body, Params, <<"">>),
        reply_letter_id = maps:get(reply_letter_id, Params, undefined),
        deposited_at = maps:get(deposited_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{letter_id := Id, from_did := From, deposited_at := At} = M)
  when is_binary(Id), is_binary(From), is_integer(At) ->
    {ok, #letter_deposited_v1{
        letter_id = Id,
        from_did = From,
        subject = maps:get(subject, M, <<"">>),
        body = maps:get(body, M, <<"">>),
        reply_letter_id = maps:get(reply_letter_id, M, undefined),
        deposited_at = At
    }};
from_map(_) ->
    {error, invalid_letter_deposited_event}.

-spec to_map(t()) -> map().
to_map(#letter_deposited_v1{} = E) ->
    #{
        event_type => <<"letter_deposited_v1">>,
        letter_id => E#letter_deposited_v1.letter_id,
        from_did => E#letter_deposited_v1.from_did,
        subject => E#letter_deposited_v1.subject,
        body => E#letter_deposited_v1.body,
        reply_letter_id => E#letter_deposited_v1.reply_letter_id,
        deposited_at => E#letter_deposited_v1.deposited_at
    }.

-spec get_letter_id(t()) -> binary().
get_letter_id(#letter_deposited_v1{letter_id = V}) -> V.

-spec get_from_did(t()) -> binary().
get_from_did(#letter_deposited_v1{from_did = V}) -> V.

-spec get_subject(t()) -> binary().
get_subject(#letter_deposited_v1{subject = V}) -> V.

-spec get_body(t()) -> binary().
get_body(#letter_deposited_v1{body = V}) -> V.

-spec get_reply_letter_id(t()) -> binary() | undefined.
get_reply_letter_id(#letter_deposited_v1{reply_letter_id = V}) -> V.

-spec get_deposited_at(t()) -> integer().
get_deposited_at(#letter_deposited_v1{deposited_at = V}) -> V.
