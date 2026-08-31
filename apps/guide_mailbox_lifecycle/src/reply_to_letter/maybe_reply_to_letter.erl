%%% @doc Handler for `reply_to_letter_v1`.
%%%
%%% The mailbox-open guard lives in the aggregate
%%% (`mailbox_aggregate:guard_open/2'); the original-letter lookup stays
%%% here. `original_sender_did` comes from the ALREADY-LOADED
%%% aggregate state (the original letter is right there, since it's
%%% stored in THIS mailbox) -- never from caller input, so a replier
%%% cannot misdirect a reply to someone other than who actually sent it.
%%%
%%% `dispatch/1` is genuinely two dispatches, not one: `execute/2`/
%%% `apply/2` only ever touch ONE aggregate's stream (this replier's own
%%% mailbox), so the actual delivery of the reply into the ORIGINAL
%%% SENDER's mailbox is a second, separate dispatch chained here -- the
%%% right layer for it, since `dispatch/1` is the I/O boundary, not the
%%% aggregate's business-rule layer.
%%% @end
-module(maybe_reply_to_letter).

-export([handle_from_map/2, handle/2, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(mailbox_state:state(), map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(State, Payload) ->
    case reply_to_letter_v1:from_map(Payload) of
        {ok, Cmd} -> handle(State, Cmd);
        {error, _} = E -> E
    end.

-spec handle(mailbox_state:state(), reply_to_letter_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(State, Cmd) ->
    case reply_to_letter_v1:validate(Cmd) of
        ok -> decide_letter(State, Cmd);
        {error, _} = E -> E
    end.

decide_letter(State, Cmd) ->
    LetterId = reply_to_letter_v1:get_letter_id(Cmd),
    case mailbox_state:get_letter(State, LetterId) of
        undefined ->
            {error, letter_not_found};
        #{archived := true} ->
            {error, letter_archived};
        #{from_did := OriginalSenderDid} ->
            Event = letter_replied_v1:new(#{
                letter_id => LetterId,
                original_sender_did => OriginalSenderDid,
                subject => reply_to_letter_v1:get_subject(Cmd),
                body => reply_to_letter_v1:get_body(Cmd)
            }),
            {ok, [letter_replied_v1:to_map(Event)]}
    end.

%% @doc Dispatch via evoq. First marks the original letter replied on the
%% replier's own stream; on success, delivers the actual reply into the
%% original sender's mailbox as a second dispatch. If that second step
%% fails (e.g. the original sender since closed their mailbox), the first
%% step has already committed -- reported explicitly rather than lost.
-spec dispatch(reply_to_letter_v1:t()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()} | {error, {replied_but_delivery_failed, term()}}.
dispatch(Cmd) ->
    CmdMap = reply_to_letter_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = reply_to_letter_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = reply_to_letter_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    case evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }) of
        {ok, Version, [ReplyEventMap | _] = Events} ->
            deliver_reply(Cmd, ReplyEventMap, Version, Events);
        {error, _} = E ->
            E
    end.

deliver_reply(Cmd, ReplyEventMap, Version, Events) ->
    DepositParams = #{
        to_citizen_did => maps:get(original_sender_did, ReplyEventMap),
        from_did => reply_to_letter_v1:get_citizen_did(Cmd),
        subject => maps:get(subject, ReplyEventMap),
        body => maps:get(body, ReplyEventMap),
        letter_id => maps:get(reply_letter_id, ReplyEventMap),
        reply_letter_id => maps:get(letter_id, ReplyEventMap)
    },
    case deposit_letter_v1:new(DepositParams) of
        {ok, DepositCmd} -> deliver_or_report(DepositCmd, Version, Events);
        {error, Reason} -> {error, {replied_but_delivery_failed, Reason}}
    end.

deliver_or_report(DepositCmd, Version, Events) ->
    case maybe_deposit_letter:dispatch(DepositCmd) of
        {ok, _DepositVersion, _DepositEvents} -> {ok, Version, Events};
        {error, Reason} -> {error, {replied_but_delivery_failed, Reason}}
    end.
