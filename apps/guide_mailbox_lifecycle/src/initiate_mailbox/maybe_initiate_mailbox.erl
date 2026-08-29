%%% @doc Handler for `initiate_mailbox_v1'.
%%%
%%% Pure: the "already initiated" guard lives in the aggregate
%%% (`mailbox_aggregate:do_execute/3'), not here -- this handler only
%%% validates the payload and builds the event, same split as
%%% `guide_repo_lifecycle''s `maybe_initiate_repo'.
%%% @end
-module(maybe_initiate_mailbox).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case initiate_mailbox_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(initiate_mailbox_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case initiate_mailbox_v1:validate(Cmd) of
        ok ->
            Event = mailbox_initiated_v1:new(#{citizen_did => initiate_mailbox_v1:get_citizen_did(Cmd)}),
            {ok, [mailbox_initiated_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(initiate_mailbox_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = initiate_mailbox_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = initiate_mailbox_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = initiate_mailbox_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_dispatcher:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
