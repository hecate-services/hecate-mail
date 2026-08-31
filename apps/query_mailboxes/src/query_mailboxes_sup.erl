%% @doc Supervises the QRY department. No standing children -- each
%% desk's responder is spawned per-call by `macula_response' via the
%% capability advertised in `hecate_mail_service:capabilities/0'. This
%% app exists so the release loads its modules and starts it in
%% dependency order relative to `project_mailboxes'.
-module(query_mailboxes_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
