%%% @doc Event `letter_replied_v1`.
%%%
%%% Lives on the REPLIER's own mailbox stream, marking the original
%%% letter as answered. Carries everything `maybe_reply_to_letter`'s
%%% `dispatch/1` needs to then deposit the actual reply into the
%%% original sender's mailbox as a SEPARATE dispatch (see that module) --
%%% `original_sender_did` and a freshly-minted `reply_letter_id` so both
%%% sides of the reply agree on the new letter's identity. Also carries
%%% `citizen_did' (the REPLIER's own DID, distinct from
%%% `original_sender_did'): the mailbox stream address is a one-way
%%% 128-bit digest of the DID (reckon-db's own stream-id contract
%%% requires it, see `mailbox_aggregate:stream_id/1''s doc), so
%%% `letter_lifecycle_to_mailboxes' reads it directly rather than
%%% trying to recover it from `stream_id'.
-module(letter_replied_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_letter_id/1, get_citizen_did/1, get_original_sender_did/1, get_reply_letter_id/1,
         get_subject/1, get_body/1, get_replied_at/1]).

-record(letter_replied_v1, {
    letter_id :: binary(),
    citizen_did :: binary(),
    original_sender_did :: binary(),
    reply_letter_id :: binary(),
    subject :: binary(),
    body :: binary(),
    replied_at :: integer()
}).

-opaque t() :: #letter_replied_v1{}.
-export_type([t/0]).

event_type() -> <<"letter_replied_v1">>.

-spec new(map()) -> t().
new(#{letter_id := Id, citizen_did := CitizenDid, original_sender_did := To} = Params) ->
    #letter_replied_v1{
        letter_id = Id,
        citizen_did = CitizenDid,
        original_sender_did = To,
        reply_letter_id = maps:get(reply_letter_id, Params, mint_reply_letter_id()),
        subject = maps:get(subject, Params, <<"">>),
        body = maps:get(body, Params, <<"">>),
        replied_at = maps:get(replied_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{letter_id := Id, citizen_did := CitizenDid, original_sender_did := To,
           reply_letter_id := RId, replied_at := At} = M)
  when is_binary(Id), is_binary(CitizenDid), is_binary(To), is_binary(RId), is_integer(At) ->
    {ok, #letter_replied_v1{
        letter_id = Id,
        citizen_did = CitizenDid,
        original_sender_did = To,
        reply_letter_id = RId,
        subject = maps:get(subject, M, <<"">>),
        body = maps:get(body, M, <<"">>),
        replied_at = At
    }};
from_map(_) ->
    {error, invalid_letter_replied_event}.

-spec to_map(t()) -> map().
to_map(#letter_replied_v1{} = E) ->
    #{
        event_type => <<"letter_replied_v1">>,
        letter_id => E#letter_replied_v1.letter_id,
        citizen_did => E#letter_replied_v1.citizen_did,
        original_sender_did => E#letter_replied_v1.original_sender_did,
        reply_letter_id => E#letter_replied_v1.reply_letter_id,
        subject => E#letter_replied_v1.subject,
        body => E#letter_replied_v1.body,
        replied_at => E#letter_replied_v1.replied_at
    }.

-spec get_letter_id(t()) -> binary().
get_letter_id(#letter_replied_v1{letter_id = V}) -> V.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#letter_replied_v1{citizen_did = V}) -> V.

-spec get_original_sender_did(t()) -> binary().
get_original_sender_did(#letter_replied_v1{original_sender_did = V}) -> V.

-spec get_reply_letter_id(t()) -> binary().
get_reply_letter_id(#letter_replied_v1{reply_letter_id = V}) -> V.

-spec get_subject(t()) -> binary().
get_subject(#letter_replied_v1{subject = V}) -> V.

-spec get_body(t()) -> binary().
get_body(#letter_replied_v1{body = V}) -> V.

-spec get_replied_at(t()) -> integer().
get_replied_at(#letter_replied_v1{replied_at = V}) -> V.

mint_reply_letter_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16)).
