%%% @doc RESPONDER for the `hecate_mail.archive_letter` mesh capability.
%%%
%%% Gated behind `mailbox_ownership_proof': archiving acts on the
%%% caller's own mailbox, so the caller must prove they hold the
%%% private key for `citizen_did' before this dispatches anything.
%%% @end
-module(archive_letter_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

-define(PROCEDURE, <<"hecate_mail.archive_letter">>).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    CitizenDid = hecate_om_wire:field(citizen_did, Payload),
    Proof = hecate_om_wire:field(proof, Payload, #{}),
    Reply = proven_reply(mailbox_ownership_proof:verify(CitizenDid, Proof, ?PROCEDURE), Payload),
    {reply, Reply, State}.

proven_reply(ok, Payload) ->
    Params = #{
        citizen_did => hecate_om_wire:field(citizen_did, Payload),
        letter_id => hecate_om_wire:field(letter_id, Payload)
    },
    case archive_letter_v1:new(Params) of
        {ok, Cmd} -> reply_for(archive_letter_v1:get_letter_id(Cmd), maybe_archive_letter:dispatch(Cmd));
        {error, Reason} -> #{ok => 0, error => reason_to_binary(Reason)}
    end;
proven_reply({error, Reason}, _Payload) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

reply_for(LetterId, {ok, _Version, _Events}) ->
    #{ok => 1, letter_id => LetterId};
reply_for(_LetterId, {error, Reason}) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
