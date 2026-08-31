%%% @doc Handler for `deposit_letter_v1`.
%%%
%%% Pure: the `mailbox_not_opened'/`mailbox_closed'/`mailbox_archived'
%%% guards live in the aggregate (`mailbox_aggregate:guard_open/2'), not
%%% here. Deposit does NOT auto-open a mailbox on a citizen's behalf --
%%% letting any caller vivify a mailbox for a DID that never opened one
%%% would let a stranger populate a directory entry nobody asked for.
%%%
%%% No de-duplication on `letter_id` here: this is a single-aggregate
%%% write, and checking "does this letter_id already exist" against
%%% current state would make a retried deposit with the same id silently
%%% do nothing, which is a bigger surprise for a genuine second letter
%%% that happens to collide than the deposit_letter_responder generating
%%% a fresh id per call already prevents. If idempotent retry ever
%%% becomes a real need, it belongs at the responder layer, not here.
%%% @end
-module(maybe_deposit_letter).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case deposit_letter_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(deposit_letter_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case deposit_letter_v1:validate(Cmd) of
        ok ->
            Event = letter_deposited_v1:new(#{
                letter_id => deposit_letter_v1:get_letter_id(Cmd),
                from_did => deposit_letter_v1:get_from_did(Cmd),
                subject => deposit_letter_v1:get_subject(Cmd),
                body => deposit_letter_v1:get_body(Cmd),
                reply_letter_id => deposit_letter_v1:get_reply_letter_id(Cmd)
            }),
            {ok, [letter_deposited_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event against the
%% RECIPIENT's own mailbox stream (`deposit_letter_v1:stream_id/1` keys
%% on `to_citizen_did`, not the depositor).
-spec dispatch(deposit_letter_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = deposit_letter_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = deposit_letter_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = deposit_letter_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
