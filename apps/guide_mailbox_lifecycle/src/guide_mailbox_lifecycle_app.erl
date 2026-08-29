%%% @doc OTP application entry for guide_mailbox_lifecycle.
%%%
%%% No boot work of its own: the reckon-db store (`hecate_mail_store`)
%%% and its evoq subscription are opened by `hecate_om:boot/1` before any
%%% app's `start/2` runs (this service exports `store_id/0`+`data_dir/0`
%%% -- see `hecate_mail_service.erl`), and this app's own desks are pure
%%% command/event/handler modules with no processes to start yet.
-module(guide_mailbox_lifecycle_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> guide_mailbox_lifecycle_sup:start_link().

stop(_State) -> ok.
