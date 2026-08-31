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

%% decode_did/1 -- the wire hands hex TEXT, not raw bytes (macula-cli's
%% JSON->CBOR bridge sends every string as text, confirmed against its
%% own wirevalue.FromJSON source).

decodes_wire_hex_text_to_raw_bytes_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    HexDid = binary:encode_hex(Did, lowercase),
    ?assertEqual(Did, mailbox_ownership_proof:decode_did(HexDid)).

passes_through_already_raw_bytes_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    ?assertEqual(Did, mailbox_ownership_proof:decode_did(Did)).

rejects_malformed_hex_as_undefined_test() ->
    ?assertEqual(undefined, mailbox_ownership_proof:decode_did(<<"not-hex-at-all-zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz">>)).

%% A full proof as it actually arrives over the wire: citizen_did AND
%% signature both hex text (what macula-cli identity sign prints and
%% what a caller's mesh_call args carry), not raw bytes.

accepts_a_genuine_proof_shaped_exactly_like_the_wire_test() ->
    KeyPair = macula_identity:generate(),
    Did = macula_identity:public(KeyPair),
    Ts = erlang:system_time(millisecond),
    RawSig = macula_identity:sign(mailbox_ownership_proof:message(Did, Ts, ?PROC), KeyPair),
    WireDid = binary:encode_hex(Did, lowercase),
    WireProof = #{timestamp => Ts, signature => binary:encode_hex(RawSig, lowercase)},
    DecodedDid = mailbox_ownership_proof:decode_did(WireDid),
    ?assertEqual(ok, mailbox_ownership_proof:verify(DecodedDid, WireProof, ?PROC)).
