%%% @doc RESPONDER for the `hecate_mail.get_letter` mesh capability.
%%%
%%% Gated behind `mailbox_ownership_proof', same as `get_mailbox' --
%%% see `get_mailbox_by_citizen_responder' for why. Fetching a single
%%% letter marks it read too, same implicit-read rule.
%%% @end
-module(get_letter_by_id_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

-define(PROCEDURE, <<"hecate_mail.get_letter">>).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    CitizenDid = hecate_om_wire:field(citizen_did, Payload),
    LetterId = hecate_om_wire:field(letter_id, Payload),
    Proof = hecate_om_wire:field(proof, Payload, #{}),
    Reply = proven_reply(mailbox_ownership_proof:verify(CitizenDid, Proof, ?PROCEDURE),
                         CitizenDid, LetterId),
    {reply, Reply, State}.

proven_reply(ok, CitizenDid, LetterId) ->
    fetched(mailboxes_read_model:find(CitizenDid, LetterId), CitizenDid, LetterId);
proven_reply({error, Reason}, _CitizenDid, _LetterId) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

fetched({ok, Doc}, CitizenDid, _LetterId) ->
    maybe_mark_read(CitizenDid, Doc),
    #{ok => 1, letter => mailboxes_read_model:to_wire(Doc)};
fetched({error, not_found}, _CitizenDid, _LetterId) ->
    #{ok => 0, error => <<"not_found">>}.

maybe_mark_read(CitizenDid, #{<<"read">> := false, <<"letter_id">> := LetterId}) ->
    case mark_letter_read_v1:new(#{citizen_did => CitizenDid, letter_id => LetterId}) of
        {ok, Cmd} -> _ = maybe_mark_letter_read:dispatch(Cmd), ok;
        {error, _} -> ok
    end;
maybe_mark_read(_CitizenDid, _AlreadyRead) ->
    ok.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
