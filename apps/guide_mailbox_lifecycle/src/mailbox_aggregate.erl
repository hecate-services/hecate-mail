%%% @doc Aggregate for the mailbox domain.
%%%
%%% One mailbox per citizen. Stream: `mailbox-{citizen_did}'. Lifecycle:
%%% `initiate_mailbox' (birth) -> `open_mailbox' <-> `close_mailbox'
%%% (repeatable) -> `archive_mailbox' (death) -> `unarchive_mailbox'
%%% (rebirth), mirroring hecate-whiteboard's `archive_board'/
%%% `unarchive_board' pair.
%%%
%%% Status/lifecycle GATING lives here, in `execute/2', not in the desk
%%% handlers -- same split as `guide_repo_lifecycle''s `repo_aggregate'
%%% (`guard_live/2'). A handler only sees the aggregate at all when it
%%% needs to look inside it (a letter lookup); the pure lifecycle desks
%%% take just the command payload.
%%% @end
-module(mailbox_aggregate).
-behaviour(evoq_aggregate).

-include("mailbox_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> mailbox_state.

-spec stream_id(binary()) -> binary().
stream_id(CitizenDid) ->
    <<"mailbox-", CitizenDid/binary>>.

init(CitizenDid) ->
    {ok, mailbox_state:new(CitizenDid)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    mailbox_state:apply_event(State, Event).

%%--------------------------------------------------------------------
%% Command routing
%%--------------------------------------------------------------------

do_execute(initiate_mailbox_v1, State, Payload) ->
    case evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_INITIATED) of
        true  -> {error, already_initiated};
        false -> maybe_initiate_mailbox:handle_from_map(Payload)
    end;

do_execute(open_mailbox_v1, State, Payload) ->
    guard_live(State, fun() -> do_open(State, Payload) end);

do_execute(close_mailbox_v1, State, Payload) ->
    guard_live(State, fun() -> do_close(State, Payload) end);

do_execute(archive_mailbox_v1, State, Payload) ->
    case {evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_INITIATED),
          evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_ARCHIVED)} of
        {false, _}    -> {error, not_initiated};
        {true, true}  -> {error, already_archived};
        {true, false} -> maybe_archive_mailbox:handle_from_map(Payload)
    end;

do_execute(unarchive_mailbox_v1, State, Payload) ->
    case evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_ARCHIVED) of
        false -> {error, not_archived};
        true  -> maybe_unarchive_mailbox:handle_from_map(Payload)
    end;

do_execute(deposit_letter_v1, State, Payload) ->
    guard_open(State, fun() -> maybe_deposit_letter:handle_from_map(Payload) end);

do_execute(mark_letter_read_v1, State, Payload) ->
    guard_open(State, fun() -> maybe_mark_letter_read:handle_from_map(State, Payload) end);

do_execute(reply_to_letter_v1, State, Payload) ->
    guard_open(State, fun() -> maybe_reply_to_letter:handle_from_map(State, Payload) end);

do_execute(archive_letter_v1, State, Payload) ->
    guard_open(State, fun() -> maybe_archive_letter:handle_from_map(State, Payload) end);

do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.

do_open(State, Payload) ->
    case evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_OPEN) of
        true  -> {error, already_open};
        false -> maybe_open_mailbox:handle_from_map(Payload)
    end.

do_close(State, Payload) ->
    case evoq_bit_flags:has(mailbox_state:status(State), ?MAILBOX_OPEN) of
        false -> {error, not_open};
        true  -> maybe_close_mailbox:handle_from_map(Payload)
    end.

%%--------------------------------------------------------------------
%% Guards
%%--------------------------------------------------------------------

%% @doc Initiated, not archived. Used by the open/close toggle, which
%% additionally checks the OPEN bit itself once past this guard.
guard_live(State, Fun) ->
    Status = mailbox_state:status(State),
    case {evoq_bit_flags:has(Status, ?MAILBOX_INITIATED),
          evoq_bit_flags:has(Status, ?MAILBOX_ARCHIVED)} of
        {false, _}    -> {error, not_initiated};
        {true, true}  -> {error, archived};
        {true, false} -> Fun()
    end.

%% @doc Initiated, not archived, and currently OPEN. Every letter-affecting
%% command needs this: mail can only move while the mailbox is actively
%% open, and closing (or archiving) leaves existing letters untouched but
%% unreachable until the mailbox opens again.
guard_open(State, Fun) ->
    Status = mailbox_state:status(State),
    case {evoq_bit_flags:has(Status, ?MAILBOX_INITIATED),
          evoq_bit_flags:has(Status, ?MAILBOX_ARCHIVED),
          evoq_bit_flags:has(Status, ?MAILBOX_OPEN)} of
        {false, _, _}        -> {error, mailbox_not_opened};
        {true, true, _}      -> {error, mailbox_archived};
        {true, false, false} -> {error, mailbox_closed};
        {true, false, true}  -> Fun()
    end.
