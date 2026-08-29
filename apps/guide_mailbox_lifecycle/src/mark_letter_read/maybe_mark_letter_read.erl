%%% @doc Handler for `mark_letter_read_v1`.
%%%
%%% The mailbox-open guard lives in the aggregate
%%% (`mailbox_aggregate:guard_open/2'); the letter-existence check stays
%%% here since it needs to look inside state at THIS mailbox's letters,
%%% something the aggregate's own flag-only guards don't do. Marking an
%%% already-read letter read again is idempotent (`{ok, []}`, no new
%%% event) rather than an error -- a caller re-fetching a mailbox and
%%% re-marking read shouldn't need to track what it already marked.
%%% @end
-module(maybe_mark_letter_read).

-export([handle_from_map/2, handle/2, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(mailbox_state:state(), map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(State, Payload) ->
    case mark_letter_read_v1:from_map(Payload) of
        {ok, Cmd} -> handle(State, Cmd);
        {error, _} = E -> E
    end.

-spec handle(mailbox_state:state(), mark_letter_read_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(State, Cmd) ->
    case mark_letter_read_v1:validate(Cmd) of
        ok -> decide_letter(State, Cmd);
        {error, _} = E -> E
    end.

decide_letter(State, Cmd) ->
    LetterId = mark_letter_read_v1:get_letter_id(Cmd),
    case mailbox_state:get_letter(State, LetterId) of
        undefined ->
            {error, letter_not_found};
        #{read := true} ->
            {ok, []};
        #{archived := true} ->
            {error, letter_archived};
        _Letter ->
            Event = letter_read_v1:new(#{letter_id => LetterId}),
            {ok, [letter_read_v1:to_map(Event)]}
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(mark_letter_read_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = mark_letter_read_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = mark_letter_read_v1,
        aggregate_type = mailbox_aggregate,
        aggregate_id = mark_letter_read_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_dispatcher:dispatch(EvoqCmd, #{
        store_id => hecate_mail_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
