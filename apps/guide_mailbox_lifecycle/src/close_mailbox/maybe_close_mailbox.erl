%%% @doc Handler for `close_mailbox_v1`.
%%%
%%% Business rule: only an open mailbox can be closed. Closing letters'
%%% own state is untouched -- they stay exactly as they were (read or
%%% not, archived or not) so re-opening later shows the mailbox as it
%%% was left, not wiped.
%%% @end
-module(maybe_close_mailbox).

-export([handle_from_map/2, handle/2, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(mailbox_state:state(), map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(State, Payload) ->
    case close_mailbox_v1:from_map(Payload) of
        {ok, Cmd} -> handle(State, Cmd);
        {error, _} = E -> E
    end.

-spec handle(mailbox_state:state(), close_mailbox_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(State, Cmd) ->
    case close_mailbox_v1:validate(Cmd) of
        ok -> decide(mailbox_state:status(State), Cmd);
        {error, _} = E -> E
    end.

decide(open, Cmd) ->
    Event = mailbox_closed_v1:new(#{citizen_did => close_mailbox_v1:get_citizen_did(Cmd)}),
    {ok, [mailbox_closed_v1:to_map(Event)]};
decide(closed, _Cmd) ->
    {error, not_open};
decide(unopened, _Cmd) ->
    {error, not_open}.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(close_mailbox_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = close_mailbox_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = close_mailbox_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = close_mailbox_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_dispatcher:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
