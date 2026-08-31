%%% @doc Handler for `close_mailbox_v1'.
%%%
%%% Pure: the `not_initiated'/`archived'/`not_open' guards live in the
%%% aggregate. Closing leaves letters' own state untouched -- they stay
%%% exactly as they were (read or not, archived or not) so re-opening
%%% later shows the mailbox as it was left, not wiped.
%%% @end
-module(maybe_close_mailbox).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case close_mailbox_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(close_mailbox_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case close_mailbox_v1:validate(Cmd) of
        ok ->
            Event = mailbox_closed_v1:new(#{citizen_did => close_mailbox_v1:get_citizen_did(Cmd)}),
            {ok, [mailbox_closed_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

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
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
