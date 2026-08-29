%%% @doc RESPONDER for the `hecate_mail.open_mailbox` mesh capability.
%%%
%%% Any citizen can open their own mailbox by DID -- no authorization
%%% needed here beyond "you're naming a DID," since opening a mailbox
%%% doesn't disclose anything (see the caller-identity-verification open
%%% question in this repo's plans/ for why the READ side can't say the
%%% same).
%%% @end
-module(open_mailbox_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    CitizenDid = hecate_om_wire:field(citizen_did, Payload),
    Reply = case open_mailbox_v1:new(#{citizen_did => CitizenDid}) of
        {ok, Cmd} -> reply_for(maybe_open_mailbox:dispatch(Cmd));
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
