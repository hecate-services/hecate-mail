%%% @doc Tests for the mailbox aggregate and its six desks, exercised
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

open_cmd() -> #{command_type => open_mailbox_v1, citizen_did => ?CITIZEN}.

deposit_cmd(LetterId) ->
    #{command_type => deposit_letter_v1, letter_id => LetterId,
      to_citizen_did => ?CITIZEN, from_did => ?SENDER,
      subject => <<"hello">>, body => <<"can you build X?">>}.

%%--------------------------------------------------------------------
%% open_mailbox
%%--------------------------------------------------------------------

open_mailbox_from_unopened_test() ->
    {{ok, [Event]}, State} = step(new_state(), open_cmd()),
    ?assertEqual(<<"mailbox_opened_v1">>, maps:get(event_type, Event)),
    ?assertEqual(open, mailbox_state:status(State)).

open_mailbox_twice_is_rejected_test() ->
    {_, State1} = step(new_state(), open_cmd()),
    {Result, _State2} = step(State1, open_cmd()),
    ?assertEqual({error, already_open}, Result).

reopen_a_closed_mailbox_succeeds_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}),
    ?assertEqual(closed, mailbox_state:status(S2)),
    {{ok, _}, S3} = step(S2, open_cmd()),
    ?assertEqual(open, mailbox_state:status(S3)).

%%--------------------------------------------------------------------
%% deposit_letter
%%--------------------------------------------------------------------

deposit_before_open_is_rejected_test() ->
    {Result, _} = step(new_state(), deposit_cmd(<<"letter-1">>)),
    ?assertEqual({error, mailbox_not_opened}, Result).

deposit_into_open_mailbox_succeeds_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {{ok, [Event]}, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    ?assertEqual(<<"letter_deposited_v1">>, maps:get(event_type, Event)),
    Letter = mailbox_state:get_letter(S2, <<"letter-1">>),
    ?assertEqual(?SENDER, maps:get(from_did, Letter)),
    ?assertEqual(false, maps:get(read, Letter)),
    ?assertEqual(false, maps:get(archived, Letter)).

deposit_into_closed_mailbox_is_rejected_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}),
    {Result, _} = step(S2, deposit_cmd(<<"letter-1">>)),
    ?assertEqual({error, mailbox_closed}, Result).

%%--------------------------------------------------------------------
%% mark_letter_read
%%--------------------------------------------------------------------

mark_unknown_letter_read_is_rejected_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {Result, _} = step(S1, #{command_type => mark_letter_read_v1,
                              citizen_did => ?CITIZEN, letter_id => <<"nope">>}),
    ?assertEqual({error, letter_not_found}, Result).

mark_letter_read_succeeds_and_is_idempotent_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    ReadCmd = #{command_type => mark_letter_read_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>},
    {{ok, [Event]}, S3} = step(S2, ReadCmd),
    ?assertEqual(<<"letter_read_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, maps:get(read, mailbox_state:get_letter(S3, <<"letter-1">>))),
    %% Idempotent: marking read again produces no new event, no error.
    {{ok, []}, S4} = step(S3, ReadCmd),
    ?assertEqual(true, maps:get(read, mailbox_state:get_letter(S4, <<"letter-1">>))).

%%--------------------------------------------------------------------
%% archive_letter
%%--------------------------------------------------------------------

archive_letter_succeeds_and_is_idempotent_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    ArchiveCmd = #{command_type => archive_letter_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>},
    {{ok, [Event]}, S3} = step(S2, ArchiveCmd),
    ?assertEqual(<<"letter_archived_v1">>, maps:get(event_type, Event)),
    ?assertEqual(true, maps:get(archived, mailbox_state:get_letter(S3, <<"letter-1">>))),
    {{ok, []}, _S4} = step(S3, ArchiveCmd).

archiving_then_marking_read_is_rejected_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    {_, S3} = step(S2, #{command_type => archive_letter_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>}),
    {Result, _} = step(S3, #{command_type => mark_letter_read_v1, citizen_did => ?CITIZEN, letter_id => <<"letter-1">>}),
    ?assertEqual({error, letter_archived}, Result).

%%--------------------------------------------------------------------
%% reply_to_letter
%%--------------------------------------------------------------------

reply_to_letter_marks_replied_and_names_original_sender_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, deposit_cmd(<<"letter-1">>)),
    ReplyCmd = #{command_type => reply_to_letter_v1, citizen_did => ?CITIZEN,
                 letter_id => <<"letter-1">>, subject => <<"re: hello">>, body => <<"yes, I can">>},
    {{ok, [Event]}, S3} = step(S2, ReplyCmd),
    ?assertEqual(<<"letter_replied_v1">>, maps:get(event_type, Event)),
    %% Original sender comes from STATE, never from the command -- the
    %% replier cannot misdirect a reply to someone else.
    ?assertEqual(?SENDER, maps:get(original_sender_did, Event)),
    ?assert(is_binary(maps:get(reply_letter_id, Event))),
    ?assertEqual(true, maps:get(replied, mailbox_state:get_letter(S3, <<"letter-1">>))).

reply_to_unknown_letter_is_rejected_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {Result, _} = step(S1, #{command_type => reply_to_letter_v1, citizen_did => ?CITIZEN,
                              letter_id => <<"nope">>, subject => <<"">>, body => <<"">>}),
    ?assertEqual({error, letter_not_found}, Result).

%%--------------------------------------------------------------------
%% close_mailbox
%%--------------------------------------------------------------------

close_unopened_mailbox_is_rejected_test() ->
    {Result, _} = step(new_state(), #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}),
    ?assertEqual({error, not_open}, Result).

close_already_closed_mailbox_is_rejected_test() ->
    {_, S1} = step(new_state(), open_cmd()),
    {_, S2} = step(S1, #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}),
    {Result, _} = step(S2, #{command_type => close_mailbox_v1, citizen_did => ?CITIZEN}),
    ?assertEqual({error, not_open}, Result).

%%--------------------------------------------------------------------
%% Unknown command
%%--------------------------------------------------------------------

unknown_command_is_rejected_test() ->
    {Result, _} = step(new_state(), #{command_type => not_a_real_command}),
    ?assertEqual({error, unknown_command}, Result).
