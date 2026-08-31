%% @doc Supervises the PRJ department: one evoq_projection worker
%% turning the letter lifecycle into `mailboxes_read_model'.
-module(project_mailboxes_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(letter_lifecycle_to_mailboxes, evoq_projection, start_link,
              [letter_lifecycle_to_mailboxes, #{}, #{}])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

worker(Id, Module, Function, Args) ->
    #{
        id       => Id,
        start    => {Module, Function, Args},
        restart  => permanent,
        shutdown => 5000,
        type     => worker,
        modules  => [Module]
    }.
