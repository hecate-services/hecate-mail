%%% @doc Supervises this app's own processes.
%%%
%%% No children yet: every desk here is a stateless command/event/handler
%%% module invoked on demand by `evoq_command_router` (which manages its own
%%% aggregate-process lifecycle via the evoq application, not this
%%% supervisor). Add a desk-owned worker/desk supervisor here if a future
%%% slice needs one (a listener, an emitter) -- per this workspace's
%%% vertical-slicing rule, it would get its own child spec here, never a
%%% shared "listeners" folder.
-module(guide_mailbox_lifecycle_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
