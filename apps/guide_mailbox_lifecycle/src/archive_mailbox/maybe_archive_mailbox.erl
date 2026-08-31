%%% @doc Handler for `archive_mailbox_v1'.
%%%
%%% Pure: the `not_initiated'/`already_archived' guards live in the
%%% aggregate, not here. Deliberately independent of the open/closed
%%% toggle -- an abandoned mailbox can be archived whether it was last
%%% left open or closed.
%%% @end
-module(maybe_archive_mailbox).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case archive_mailbox_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(archive_mailbox_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case archive_mailbox_v1:validate(Cmd) of
        ok ->
            Event = mailbox_archived_v1:new(#{citizen_did => archive_mailbox_v1:get_citizen_did(Cmd)}),
            {ok, [mailbox_archived_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(archive_mailbox_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = archive_mailbox_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = archive_mailbox_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = archive_mailbox_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
