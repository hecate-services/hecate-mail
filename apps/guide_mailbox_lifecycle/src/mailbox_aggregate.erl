%%% @doc Aggregate for the mailbox domain.
%%%
%%% One mailbox per citizen. Stream: `mailbox-{citizen_did}'. Routes each
%%% command to its own desk's handler, which enforces the business rule
%%% (can this slip be added, given the mailbox's current status) and
%%% produces the matching event(s). This module itself holds no business
%%% logic -- it is the seam evoq calls into, nothing more.
%%% @end
-module(mailbox_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> mailbox_state.

-spec stream_id(binary()) -> binary().
stream_id(CitizenDid) ->
    <<"mailbox-", CitizenDid/binary>>.

init(CitizenDid) ->
    {ok, mailbox_state:new(CitizenDid)}.

execute(State, #{command_type := open_mailbox_v1} = Payload) ->
    maybe_open_mailbox:handle_from_map(State, Payload);
execute(State, #{command_type := deposit_letter_v1} = Payload) ->
    maybe_deposit_letter:handle_from_map(State, Payload);
execute(State, #{command_type := mark_letter_read_v1} = Payload) ->
    maybe_mark_letter_read:handle_from_map(State, Payload);
execute(State, #{command_type := reply_to_letter_v1} = Payload) ->
    maybe_reply_to_letter:handle_from_map(State, Payload);
execute(State, #{command_type := archive_letter_v1} = Payload) ->
    maybe_archive_letter:handle_from_map(State, Payload);
execute(State, #{command_type := close_mailbox_v1} = Payload) ->
    maybe_close_mailbox:handle_from_map(State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    mailbox_state:apply_event(State, Event).
