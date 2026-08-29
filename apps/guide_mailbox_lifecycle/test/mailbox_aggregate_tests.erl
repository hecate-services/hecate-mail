%%% @doc Tests for the mailbox aggregate and its nine desks, exercised
%%% through `init/1' + `execute/2' + `apply/2' -- the same three
%%% callbacks evoq itself drives, with no mesh, no store, no process.
%%% Per this workspace's own testing convention (evoq's aggregates.md
%%% guide, "Testing Aggregates"): pure functions, zero mesh, runs in the
%%% default `rebar3 eunit' gate.
-module(mailbox_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CITIZEN, <<"did:macula:alice">>).
-define(SENDER, <<"did:macula:bob">>).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

new_state() ->
    {ok, S} = mailbox_aggregate:init(?CITIZEN),
    S.

%% Runs one command through execute/2, folds any produced events into
%% state via apply/2 (mirroring what evoq itself does), and returns the
%% new state alongside the raw result.
step(State, Payload) ->
    case mailbox_aggregate:execute(State, Payload) of
        {ok, Events} ->
            NewState = lists:foldl(fun(Event, S) -> mailbox_aggregate:apply(S, Event) end, State, Events),
            {{ok, Events}, NewState};
        {error, _} = Error ->
            {Error, State}
    end.

%% Runs a whole command list in order, threading state through, and
%% returns the final state -- for setting up scenarios where every step
%% is expected to succeed.
run(State, []) -> State;
run(State, [Cmd | Rest]) ->
    {{ok, _}, NewState} = step(State, Cmd),
    run(NewState, Rest).

initiate_cmd() -> #{command_type => initiate_mailbox_v1, citizen_did => ?CITIZEN}.
open_cmd()     -> #{command_type => open_mailbox_v1, citizen_did => ?CITIZEN}.
close_cmd()    -> #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}.
archive_mailbox_cmd()   -> #{command_type => archive_mailbox_v1, citizen_did => ?CITIZEN}.
unarchive_mailbox_cmd() -> #{command_type => unarchive_mailbox_v1, citizen_did => ?CITIZEN}.

deposit_cmd(LetterId) ->
    #{command_type => deposit_letter_v1, letter_id => LetterId,
      to_citizen_did => ?CITIZEN, from_did => ?SENDER,
      subject => <<"hello">>, body => <<"can you build X?">>}.

%% A mailbox that has been initiated and opened -- the common starting
%% point for every letter-level test.
open_mailbox_state() ->
    run(new_state(), [initiate_cmd(), open_cmd()]).

%%--------------------------------------------------------------------
%% initiate_mailbox
%%--------------------------------------------------------------------

initiate_mailbox_from_fresh_state_test() ->
    {{ok, [Event]}, State} = step(new_state(), initiate_cmd()),
    ?assertEqual(<<"mailbox_initiated_v1">>, maps:get(event_type, Event)),
    ?assertEqual(false, mailbox_state:is_open(State)),
    ?assertEqual(false, mailbox_state:is_archived(State)).

initiate_mailbox_twice_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd()]),
    {Result, _} = step(S1, initiate_cmd()),
    ?assertEqual({error, already_initiated}, Result).

%%--------------------------------------------------------------------
%% open_mailbox / close_mailbox
%%--------------------------------------------------------------------

open_without_initiating_is_rejected_test() ->
    {Result, _} = step(new_state(), open_cmd()),
    ?assertEqual({error, not_initiated}, Result).

open_mailbox_after_initiate_succeeds_test() ->
    S1 = run(new_state(), [initiate_cmd()]),
    {{ok, [Event]}, State} = step(S1, open_cmd()),
    ?assertEqual(<<"mailbox_opened_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, mailbox_state:is_open(State)).

open_mailbox_twice_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd(), open_cmd()]),
    {Result, _} = step(S1, open_cmd()),
    ?assertEqual({error, already_open}, Result).

close_without_opening_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd()]),
    {Result, _} = step(S1, close_cmd()),
    ?assertEqual({error, not_open}, Result).

close_already_closed_mailbox_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd(), open_cmd(), close_cmd()]),
    {Result, _} = step(S1, close_cmd()),
    ?assertEqual({error, not_open}, Result).

reopen_a_closed_mailbox_succeeds_test() ->
    S1 = run(new_state(), [initiate_cmd(), open_cmd(), close_cmd()]),
    ?assertEqual(false, mailbox_state:is_open(S1)),
    {{ok, _}, S2} = step(S1, open_cmd()),
    ?assertEqual(true, mailbox_state:is_open(S2)).

%%--------------------------------------------------------------------
%% archive_mailbox / unarchive_mailbox
%%--------------------------------------------------------------------

archive_uninitiated_mailbox_is_rejected_test() ->
    {Result, _} = step(new_state(), archive_mailbox_cmd()),
    ?assertEqual({error, not_initiated}, Result).

archive_mailbox_succeeds_whether_open_or_closed_test() ->
    S1 = run(new_state(), [initiate_cmd(), open_cmd()]),
    {{ok, [Event]}, S2} = step(S1, archive_mailbox_cmd()),
    ?assertEqual(<<"mailbox_archived_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, mailbox_state:is_archived(S2)).

archive_already_archived_mailbox_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd(), archive_mailbox_cmd()]),
    {Result, _} = step(S1, archive_mailbox_cmd()),
    ?assertEqual({error, already_archived}, Result).

unarchive_a_never_archived_mailbox_is_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd()]),
    {Result, _} = step(S1, unarchive_mailbox_cmd()),
    ?assertEqual({error, not_archived}, Result).

unarchive_mailbox_succeeds_and_does_not_reopen_it_test() ->
    S1 = run(new_state(), [initiate_cmd(), archive_mailbox_cmd()]),
    {{ok, [Event]}, S2} = step(S1, unarchive_mailbox_cmd()),
    ?assertEqual(<<"mailbox_unarchived_v1">>, maps:get(event_type, Event)),
    ?assertEqual(false, mailbox_state:is_archived(S2)),
    ?assertEqual(false, mailbox_state:is_open(S2)).

operations_on_an_archived_mailbox_are_rejected_test() ->
    S1 = run(new_state(), [initiate_cmd(), open_cmd(), archive_mailbox_cmd()]),
    ?assertMatch({{error, archived}, _}, step(S1, close_cmd())),
    ?assertMatch({{error, archived}, _}, step(S1, open_cmd())),
    ?assertMatch({{error, mailbox_archived}, _}, step(S1, deposit_cmd(<<"letter-x">>))).

%%--------------------------------------------------------------------
%% deposit_letter
%%--------------------------------------------------------------------

deposit_before_initiating_is_rejected_test() ->
    {Result, _} = step(new_state(), deposit_cmd(<<"letter-1">>)),
    ?assertEqual({error, mailbox_not_opened}, Result).

deposit_into_open_mailbox_succeeds_test() ->
    S1 = open_mailbox_state(),
    {{ok, [Event]}, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    ?assertEqual(<<"letter_deposited_v1">>, maps:get(event_type, Event)),
    Letter = mailbox_state:get_letter(S2, <<"letter-1">>),
    ?assertEqual(?SENDER, maps:get(from_did, Letter)),
    ?assertEqual(false, maps:get(read, Letter)),
    ?assertEqual(false, maps:get(archived, Letter)).

deposit_into_closed_mailbox_is_rejected_test() ->
    S1 = run(open_mailbox_state(), [close_cmd()]),
    {Result, _} = step(S1, deposit_cmd(<<"letter-1">>)),
    ?assertEqual({error, mailbox_closed}, Result).

%%--------------------------------------------------------------------
%% mark_letter_read
%%--------------------------------------------------------------------

mark_unknown_letter_read_is_rejected_test() ->
    S1 = open_mailbox_state(),
    {Result, _} = step(S1, #{command_type => mark_letter_read_v1,
                              citizen_did => ?CITIZEN, letter_id => <<"nope">>}),
    ?assertEqual({error, letter_not_found}, Result).

mark_letter_read_succeeds_and_is_idempotent_test() ->
    S1 = run(open_mailbox_state(), [deposit_cmd(<<"letter-1">>)]),
    ReadCmd = #{command_type => mark_letter_read_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>},
    {{ok, [Event]}, S2} = step(S1, ReadCmd),
    ?assertEqual(<<"letter_read_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, maps:get(read, mailbox_state:get_letter(S2, <<"letter-1">>))),
    %% Idempotent: marking read again produces no new event, no error.
    {{ok, []}, S3} = step(S2, ReadCmd),
    ?assertEqual(true, maps:get(read, mailbox_state:get_letter(S3, <<"letter-1">>))).

mark_letter_read_while_mailbox_closed_is_rejected_test() ->
    S1 = run(open_mailbox_state(), [deposit_cmd(<<"letter-1">>), close_cmd()]),
    {Result, _} = step(S1, #{command_type => mark_letter_read_v1,
                              citizen_did => ?CITIZEN, letter_id => <<"letter-1">>}),
    ?assertEqual({error, mailbox_closed}, Result).

%%--------------------------------------------------------------------
%% archive_letter
%%--------------------------------------------------------------------

archive_letter_succeeds_and_is_idempotent_test() ->
    S1 = run(open_mailbox_state(), [deposit_cmd(<<"letter-1">>)]),
    ArchiveCmd = #{command_type => archive_letter_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>},
    {{ok, [Event]}, S2} = step(S1, ArchiveCmd),
    ?assertEqual(<<"letter_archived_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, maps:get(archived, mailbox_state:get_letter(S2, <<"letter-1">>))),
    {{ok, []}, _S3} = step(S2, ArchiveCmd).

archiving_then_marking_read_is_rejected_test() ->
    S1 = run(open_mailbox_state(),
             [deposit_cmd(<<"letter-1">>),
              #{command_type => archive_letter_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>}]),
    {Result, _} = step(S1, #{command_type => mark_letter_read_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>}),
    ?assertEqual({error, letter_archived}, Result).

%%--------------------------------------------------------------------
%% reply_to_letter
%%--------------------------------------------------------------------

reply_to_letter_marks_replied_and_names_original_sender_test() ->
    S1 = run(open_mailbox_state(), [deposit_cmd(<<"letter-1">>)]),
    ReplyCmd = #{command_type => reply_to_letter_v1, citizen_did => ?CITIZEN,
                 letter_id => <<"letter-1">>, subject => <<"re: hello">>, body => <<"yes, I can">>},
    {{ok, [Event]}, S2} = step(S1, ReplyCmd),
    ?assertEqual(<<"letter_replied_v1">>, maps:get(event_type, Event)),
    %% Original sender comes from STATE, never from the command -- the
    %% replier cannot misdirect a reply to someone else.
    ?assertEqual(?SENDER, maps:get(original_sender_did, Event)),
    ?assert(is_binary(maps:get(reply_letter_id, Event))),
    ?assertEqual(true, maps:get(replied, mailbox_state:get_letter(S2, <<"letter-1">>))).

reply_to_unknown_letter_is_rejected_test() ->
    S1 = open_mailbox_state(),
    {Result, _} = step(S1, #{command_type => reply_to_letter_v1, citizen_did => ?CITIZEN,
                              letter_id => <<"nope">>, subject => <<"">>, body => <<"">>}),
    ?assertEqual({error, letter_not_found}, Result).

%%--------------------------------------------------------------------
%% Unknown command
%%--------------------------------------------------------------------

unknown_command_is_rejected_test() ->
    {Result, _} = step(new_state(), #{command_type => not_a_real_command}),
    ?assertEqual({error, unknown_command}, Result).
