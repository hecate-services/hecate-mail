%%% @doc Verifies a caller actually holds the private key for the
%%% citizen_did they're acting as -- the fix for
%%% plans/PLAN_HECATE_MAIL_PART3_MAILBOXES.md's open authorization
%%% question.
%%%
%%% Confirmed by reading hecate_om's vendored macula SDK directly
%%% (macula_station_link:handle_inbound_call/2): a `macula_response'
%%% handler receives only the caller's self-asserted Payload, never a
%%% verified caller identity -- the `{ucan_required, Issuer}' auth
%%% policy gates a whole procedure against one fixed issuer, not a
%%% specific caller, and the `caller' field macula_frame:call/1' does
%%% carry is structurally validated (32 bytes) but never
%%% cryptographically checked against the frame by any hop. So a
%%% capability that discloses one citizen's own data (a mailbox's
%%% contents) has to check this itself.
%%%
%%% Since a Macula DID *is* an Ed25519 public key
%%% (macula_identity:node_id() :: pubkey()), the caller proves
%%% ownership the same way any self-certifying identity does: sign a
%%% message over {citizen_did, timestamp, procedure} with the matching
%%% private key. Procedure is included so a proof minted for
%%% `get_mailbox' can't be replayed against `get_letter' (or any other
%%% gated capability); timestamp bounds replay to a short window
%%% instead of requiring a second round trip for a server-issued nonce
%%% (this is a request/response RPC, not a stream, so there is no
%%% narrower race to close).
%%%
%%% WIRE ENCODING: macula-cli's JSON->CBOR bridge (wirevalue.FromJSON)
%%% sends every JSON string as a CBOR TEXT value, never a byte string --
%%% confirmed reading it directly, no `0x'-prefix special-casing on the
%%% way in (only on the way OUT, for display). So `citizen_did' and this
%%% proof's `signature' arrive here as ASCII hex TEXT (what
%%% `macula-cli identity sign' and `mesh_hello' print), not the 32/64
%%% raw bytes the crypto actually operates on. `decode_did/1' undoes
%%% that for citizen_did (used for the signed message AND everywhere
%%% else a responder needs the raw DID); `verify/3' undoes it for the
%%% signature internally, since nothing else ever needs that one raw.
%%% @end
-module(mailbox_ownership_proof).

-export([verify/3, message/3, decode_did/1]).

-define(MAX_SKEW_MS, 60_000).

%% @doc Hex-decodes a wire-transported DID/node_id into its raw 32
%% bytes. `undefined' for anything that isn't well-formed hex of the
%% right length, rather than crashing the responder's transient
%% process on a malformed caller input -- verify/3's own byte_size
%% guard then rejects it cleanly as `invalid_citizen_did'.
-spec decode_did(term()) -> binary() | undefined.
decode_did(HexDid) when is_binary(HexDid), byte_size(HexDid) =:= 64 ->
    try binary:decode_hex(HexDid) catch error:badarg -> undefined end;
decode_did(RawDid) when is_binary(RawDid), byte_size(RawDid) =:= 32 ->
    %% Already raw bytes -- an in-VM caller (this repo's own eunit
    %% fixtures, or a future non-wire caller) never round-trips
    %% through hex at all.
    RawDid;
decode_did(_Other) ->
    undefined.

-spec message(binary(), integer(), binary()) -> binary().
message(CitizenDid, Timestamp, Procedure)
  when is_binary(CitizenDid), is_integer(Timestamp), is_binary(Procedure) ->
    <<CitizenDid/binary, Timestamp:64/big, Procedure/binary>>.

-spec verify(binary(), map(), binary()) -> ok | {error, atom()}.
verify(CitizenDid, Proof, Procedure)
  when is_binary(CitizenDid), byte_size(CitizenDid) =:= 32, is_map(Proof), is_binary(Procedure) ->
    checked_fields(maps:find(timestamp, Proof), maps:find(signature, Proof),
                   CitizenDid, Procedure);
verify(_CitizenDid, _Proof, _Procedure) ->
    {error, invalid_citizen_did}.

checked_fields({ok, Ts}, {ok, Sig}, CitizenDid, Procedure) when is_integer(Ts), is_binary(Sig) ->
    decoded_sig(decode_hex_sig(Sig), Ts, CitizenDid, Procedure);
checked_fields(_Ts, _Sig, _CitizenDid, _Procedure) ->
    {error, missing_proof}.

decode_hex_sig(Sig) when byte_size(Sig) =:= 128 ->
    try binary:decode_hex(Sig) catch error:badarg -> undefined end;
decode_hex_sig(Sig) when byte_size(Sig) =:= 64 ->
    %% Already raw -- see decode_did/1's own note on in-VM callers.
    Sig;
decode_hex_sig(_Other) ->
    undefined.

decoded_sig(undefined, _Ts, _CitizenDid, _Procedure) ->
    {error, bad_signature};
decoded_sig(Sig, Ts, CitizenDid, Procedure) ->
    fresh(Ts, CitizenDid, Sig, Procedure).

fresh(Ts, CitizenDid, Sig, Procedure) ->
    skew_checked(abs(erlang:system_time(millisecond) - Ts), Ts, CitizenDid, Sig, Procedure).

skew_checked(Skew, Ts, CitizenDid, Sig, Procedure) when Skew =< ?MAX_SKEW_MS ->
    signed(macula_identity:verify(message(CitizenDid, Ts, Procedure), Sig, CitizenDid));
skew_checked(_Skew, _Ts, _CitizenDid, _Sig, _Procedure) ->
    {error, stale_proof}.

signed(true) -> ok;
signed(false) -> {error, bad_signature}.
