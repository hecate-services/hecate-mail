%%% @doc RESPONDER for the `hecate_mail.get_mailbox` mesh capability.
%%%
%%% Gated behind `mailbox_ownership_proof' -- this discloses a citizen's
%%% own mail, so the caller must prove they hold the private key for
%%% `citizen_did'. Fetching implicitly marks every returned letter read
%%% (PART3: "a citizen fetching their own mailbox marks-as-read
%%% implicitly as part of the read, collapsing two round trips") --
%%% letters come back with the read flag AS OF fetch time, so a caller
%%% can tell what's newly arrived this round, and are marked read
%%% afterward for next time.
%%% @end
-module(get_mailbox_by_citizen_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

-define(PROCEDURE, <<"hecate_mail.get_mailbox">>).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    %% citizen_did arrives as ASCII hex TEXT over the wire, decoded once
    %% here and reused throughout -- see mailbox_ownership_proof's own
    %% doc on why.
    CitizenDid = mailbox_ownership_proof:decode_did(hecate_om_wire:field(citizen_did, Payload)),
    Proof = hecate_om_wire:field(proof, Payload, #{}),
    Reply = proven_reply(mailbox_ownership_proof:verify(CitizenDid, Proof, ?PROCEDURE), CitizenDid),
    {reply, Reply, State}.

proven_reply(ok, CitizenDid) ->
    Letters = mailboxes_read_model:list_unarchived(CitizenDid),
    lists:foreach(fun(Letter) -> maybe_mark_read(CitizenDid, Letter) end, Letters),
    #{ok => 1, letters => lists:map(fun mailboxes_read_model:to_wire/1, Letters)};
proven_reply({error, Reason}, _CitizenDid) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

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
