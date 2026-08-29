%%% @doc Handler for `open_mailbox_v1`.
%%%
%%% Business rule: a mailbox already open refuses a second open -- the
%%% Dossier Principle's "can this slip be added" question, answered by
%%% the aggregate's current status. Opening from `unopened` (first time)
%%% or `closed` (re-opening) both succeed.
%%% @end
-module(maybe_open_mailbox).

-export([handle_from_map/2, handle/2, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(mailbox_state:state(), map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(State, Payload) ->
    case open_mailbox_v1:from_map(Payload) of
        {ok, Cmd} -> handle(State, Cmd);
        {error, _} = E -> E
    end.

-spec handle(mailbox_state:state(), open_mailbox_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(State, Cmd) ->
    case open_mailbox_v1:validate(Cmd) of
        ok -> decide(mailbox_state:status(State), Cmd);
        {error, _} = E -> E
    end.

decide(open, _Cmd) ->
    {error, already_open};
decide(_UnopenedOrClosed, Cmd) ->
    Event = mailbox_opened_v1:new(#{citizen_did => open_mailbox_v1:get_citizen_did(Cmd)}),
    {ok, [mailbox_opened_v1:to_map(Event)]}.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(open_mailbox_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = open_mailbox_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = open_mailbox_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = open_mailbox_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_dispatcher:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
