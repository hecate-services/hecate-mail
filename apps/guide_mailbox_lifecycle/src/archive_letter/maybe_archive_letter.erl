%%% @doc Handler for `archive_letter_v1`.
%%%
%%% Business rule: mailbox open, letter exists. Archiving an
%%% already-archived letter is idempotent (`{ok, []}`), same reasoning as
%%% `maybe_mark_letter_read`.
%%% @end
-module(maybe_archive_letter).

-export([handle_from_map/2, handle/2, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(mailbox_state:state(), map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(State, Payload) ->
    case archive_letter_v1:from_map(Payload) of
        {ok, Cmd} -> handle(State, Cmd);
        {error, _} = E -> E
    end.

-spec handle(mailbox_state:state(), archive_letter_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(State, Cmd) ->
    case archive_letter_v1:validate(Cmd) of
        ok -> decide(State, Cmd);
        {error, _} = E -> E
    end.

decide(State, Cmd) ->
    case mailbox_state:status(State) of
        open -> decide_letter(State, Cmd);
        closed -> {error, mailbox_closed};
        unopened -> {error, mailbox_not_opened}
    end.

decide_letter(State, Cmd) ->
    LetterId = archive_letter_v1:get_letter_id(Cmd),
    case mailbox_state:get_letter(State, LetterId) of
        undefined ->
            {error, letter_not_found};
        #{archived := true} ->
            {ok, []};
        _Letter ->
            Event = letter_archived_v1:new(#{letter_id => LetterId}),
            {ok, [letter_archived_v1:to_map(Event)]}
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(archive_letter_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = archive_letter_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = archive_letter_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = archive_letter_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_dispatcher:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
