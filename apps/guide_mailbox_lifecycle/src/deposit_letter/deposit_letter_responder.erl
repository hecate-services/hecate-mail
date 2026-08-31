%%% @doc RESPONDER for the `hecate_mail.deposit_letter` mesh capability.
%%%
%%% Write-only, deliberately: unlike a mailbox read, a deposit discloses
%%% nothing about the recipient's mailbox contents, so this is safe to
%%% expose without the caller-identity verification the read side needs
%%% (see this repo's plans/ for that open question). `from_did` is
%%% self-asserted by the caller -- this responder does not verify the
%%% depositor is who they claim, matching the "postoffice delivers, does
%%% not vouch" framing throughout this plan.
%%%
%%% Both DID fields arrive as ASCII hex TEXT over the wire, decoded to
%%% raw bytes here -- see mailbox_ownership_proof's own doc on why.
%%% @end
-module(deposit_letter_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    Params = #{
        to_citizen_did => mailbox_ownership_proof:decode_did(hecate_om_wire:field(to_citizen_did, Payload)),
        from_did => mailbox_ownership_proof:decode_did(hecate_om_wire:field(from_did, Payload)),
        subject => mailbox_ownership_proof:decode_text(hecate_om_wire:field(subject, Payload, <<"">>)),
        body => mailbox_ownership_proof:decode_text(hecate_om_wire:field(body, Payload, <<"">>)),
        reply_letter_id => mailbox_ownership_proof:decode_text(hecate_om_wire:field(reply_letter_id, Payload, undefined))
    },
    Reply = case deposit_letter_v1:new(Params) of
        {ok, Cmd} -> reply_for(Cmd, maybe_deposit_letter:dispatch(Cmd));
        {error, Reason} -> #{ok => 0, error => reason_to_binary(Reason)}
    end,
    {reply, Reply, State}.

reply_for(Cmd, {ok, _Version, _Events}) ->
    #{ok => 1, letter_id => deposit_letter_v1:get_letter_id(Cmd)};
reply_for(_Cmd, {error, Reason}) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
