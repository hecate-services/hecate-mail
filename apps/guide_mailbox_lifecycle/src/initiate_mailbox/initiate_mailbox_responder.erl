%%% @doc RESPONDER for the `hecate_mail.initiate_mailbox` mesh capability.
%%%
%%% Any citizen can initiate their own mailbox by DID -- no authorization
%%% needed beyond "you're naming a DID," same trust profile as
%%% `open_mailbox_responder'.
%%%
%%% `citizen_did' arrives as ASCII hex TEXT over the wire (macula-cli's
%%% JSON->CBOR bridge sends every string as text, never bytes -- see
%%% `mailbox_ownership_proof''s own doc), decoded to raw bytes here so
%%% the stream this mailbox lives on (`mailbox-{citizen_did}') is
%%% addressed consistently with every other desk.
%%% @end
-module(initiate_mailbox_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    CitizenDid = mailbox_ownership_proof:decode_did(hecate_om_wire:field(citizen_did, Payload)),
    Reply = case initiate_mailbox_v1:new(#{citizen_did => CitizenDid}) of
        {ok, Cmd} -> reply_for(maybe_initiate_mailbox:dispatch(Cmd));
        {error, Reason} -> #{ok => 0, error => reason_to_binary(Reason)}
    end,
    {reply, Reply, State}.

reply_for({ok, _Version, _Events}) ->
    #{ok => 1};
reply_for({error, Reason}) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
