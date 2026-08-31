%%% @doc Tests for mailbox_ownership_proof -- pure crypto, zero mesh,
%%% runs in the default `rebar3 eunit' gate.
-module(mailbox_ownership_proof_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PROC, <<"hecate_mail.get_mailbox">>).

sign(KeyPair, CitizenDid, Timestamp, Procedure) ->
    macula_identity:sign(mailbox_ownership_proof:message(CitizenDid, Timestamp, Procedure), KeyPair).

fresh_proof(KeyPair, CitizenDid, Procedure) ->
    Ts = erlang:system_time(millisecond),
    #{timestamp => Ts, signature => sign(KeyPair, CitizenDid, Ts, Procedure)}.

accepts_a_genuine_fresh_proof_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    ?assertEqual(ok, mailbox_ownership_proof:verify(Did, fresh_proof(KeyPair, Did, ?PROC), ?PROC)).

rejects_a_signature_from_a_different_key_test() ->
    Impostor = macula_identity:generate(),
    Owner = macula_identity:generate(),
    Did = macula_identity:public(Owner),
    Proof = fresh_proof(Impostor, Did, ?PROC),
    ?assertEqual({error, bad_signature}, mailbox_ownership_proof:verify(Did, Proof, ?PROC)).

rejects_a_proof_minted_for_a_different_procedure_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    Proof = fresh_proof(KeyPair, Did, <<"hecate_mail.get_letter">>),
    ?assertEqual({error, bad_signature}, mailbox_ownership_proof:verify(Did, Proof, ?PROC)).

rejects_a_stale_timestamp_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    Ts = erlang:system_time(millisecond) - 120_000,
    Proof = #{timestamp => Ts, signature => sign(KeyPair, Did, Ts, ?PROC)},
    ?assertEqual({error, stale_proof}, mailbox_ownership_proof:verify(Did, Proof, ?PROC)).

rejects_a_timestamp_too_far_in_the_future_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    Ts = erlang:system_time(millisecond) + 120_000,
    Proof = #{timestamp => Ts, signature => sign(KeyPair, Did, Ts, ?PROC)},
    ?assertEqual({error, stale_proof}, mailbox_ownership_proof:verify(Did, Proof, ?PROC)).

rejects_a_missing_proof_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    ?assertEqual({error, missing_proof}, mailbox_ownership_proof:verify(Did, #{}, ?PROC)).

rejects_a_malformed_did_test() ->
    ?assertEqual({error, invalid_citizen_did},
                mailbox_ownership_proof:verify(<<"not-32-bytes">>, #{}, ?PROC)).
