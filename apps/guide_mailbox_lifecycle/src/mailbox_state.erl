%%% @doc State module for the mailbox aggregate.
%%%
%%% One mailbox per citizen, keyed by `citizen_did' (the stream id). `status'
%%% is a bit-flag integer (`mailbox_status.hrl'), not an atom -- status
%%% fields in this workspace are always bit flags, per this workspace's own
%%% guide_repo_lifecycle (`repo_state.erl') and hecate-whiteboard's
%%% `archive_board'/`unarchive_board' pair, which this desk mirrors.
%%%
%%% Letters are never deleted from state (event-sourced history is the
%%% point) -- `archived' marks a letter as no longer active without erasing
%%% it.
%%% @end
-module(mailbox_state).
-behaviour(evoq_state).

-include("mailbox_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, citizen_did/1, get_letter/2, is_open/1, is_archived/1]).

-type letter() :: #{
    letter_id => binary(),
    from_did => binary(),
    subject => binary(),
    body => binary(),
    reply_letter_id => binary() | undefined,
    read => boolean(),
    replied => boolean(),
    archived => boolean(),
    deposited_at => integer()
}.

-record(state, {
    citizen_did :: binary() | undefined,
    status = 0 :: non_neg_integer(),
    letters = #{} :: #{binary() => letter()}
}).

-type state() :: #state{}.
-export_type([state/0, letter/0]).

-spec new(binary()) -> state().
new(CitizenDid) ->
    #state{citizen_did = CitizenDid}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

-spec is_open(state()) -> boolean().
is_open(#state{status = S}) -> evoq_bit_flags:has(S, ?MAILBOX_OPEN).

-spec is_archived(state()) -> boolean().
is_archived(#state{status = S}) -> evoq_bit_flags:has(S, ?MAILBOX_ARCHIVED).

-spec citizen_did(state()) -> binary() | undefined.
citizen_did(#state{citizen_did = D}) -> D.

-spec get_letter(state(), binary()) -> letter() | undefined.
get_letter(#state{letters = Letters}, LetterId) ->
    maps:get(LetterId, Letters, undefined).

%% @doc Folds one event into state. Matched by `event_type', which is
%% always the snake_case_vN binary every event module's own `event_type/0'
%% returns -- never the record/module name directly, since this function
%% also runs during replay from the raw stored map.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"mailbox_initiated_v1">>} = Ev) ->
    S#state{
        citizen_did = maps:get(citizen_did, Ev),
        status = evoq_bit_flags:set(S#state.status, ?MAILBOX_INITIATED)
    };
apply_event(S, #{event_type := <<"mailbox_opened_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?MAILBOX_OPEN)};
apply_event(S, #{event_type := <<"mailbox_closed_v1">>}) ->
    S#state{status = evoq_bit_flags:unset(S#state.status, ?MAILBOX_OPEN)};
apply_event(S, #{event_type := <<"mailbox_archived_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?MAILBOX_ARCHIVED)};
apply_event(S, #{event_type := <<"mailbox_unarchived_v1">>}) ->
    S#state{status = evoq_bit_flags:unset(S#state.status, ?MAILBOX_ARCHIVED)};
apply_event(#state{letters = Letters} = S, #{event_type := <<"letter_deposited_v1">>} = Ev) ->
    LetterId = maps:get(letter_id, Ev),
    Letter = #{
        letter_id => LetterId,
        from_did => maps:get(from_did, Ev),
        subject => maps:get(subject, Ev),
        body => maps:get(body, Ev),
        reply_letter_id => maps:get(reply_letter_id, Ev, undefined),
        read => false,
        replied => false,
        archived => false,
        deposited_at => maps:get(deposited_at, Ev)
    },
    S#state{letters = Letters#{LetterId => Letter}};
apply_event(#state{letters = Letters} = S, #{event_type := <<"letter_read_v1">>} = Ev) ->
    LetterId = maps:get(letter_id, Ev),
    S#state{letters = mark(Letters, LetterId, read, true)};
apply_event(#state{letters = Letters} = S, #{event_type := <<"letter_replied_v1">>} = Ev) ->
    LetterId = maps:get(letter_id, Ev),
    S#state{letters = mark(Letters, LetterId, replied, true)};
apply_event(#state{letters = Letters} = S, #{event_type := <<"letter_archived_v1">>} = Ev) ->
    LetterId = maps:get(letter_id, Ev),
    S#state{letters = mark(Letters, LetterId, archived, true)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{citizen_did = D, status = St, letters = Letters}) ->
    #{citizen_did => D, status => St, letters => Letters}.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

mark(Letters, LetterId, Field, Value) ->
    case maps:find(LetterId, Letters) of
        {ok, Letter} -> Letters#{LetterId => Letter#{Field => Value}};
        error -> Letters
    end.
