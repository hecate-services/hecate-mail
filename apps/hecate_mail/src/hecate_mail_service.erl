%% @doc The hecate_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. hecate_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% IT ANNOUNCES NOTHING AND ASKS FOR NOTHING, on purpose. A service that does
%% nothing yet has no capability to offer and needs no authority from the realm.
%% Advertising a capability before it exists puts a lie on the mesh that another
%% service can find and call. Both lists grow when the thing they name exists,
%% and a generated test fails when they change, so growing them is a deliberate
%% act rather than a comment someone forgot.
-module(hecate_mail_service).

-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ==========================================================================
%% AND TWO OPTIONAL ONES, WHICH TURN THE STORE ON
%% ==========================================================================
%%
%% Generated because this service was scaffolded with `store=1'. Exporting
%% `store_id/0' and `data_dir/0' TOGETHER makes `hecate_om:boot/1' open a
%% reckon-db store before this module's `start/1' fires.
%%
%% ⚠ THE reckon-db APPLICATIONS RUN EITHER WAY. `reckon_db', `reckon_evoq',
%% `reckon_gater', `evoq', `khepri' and `ra' start with `hecate_om' whether these
%% callbacks exist or not. What the two add is a STORE: a data directory, an open
%% handle, and something written. A sibling service claimed for months that they
%% suppressed the whole stack while six of its thirty-one running applications
%% quietly disproved it.
%%
%% ⚠⚠ AND `config/sys.config.src' MUST CARRY THE `evoq' BLOCK, which is why it was
%% generated with one. hecate_om starts a per-store evoq subscription that reads
%% the global log, and that crashes on `{not_configured, event_store_adapter}'
%% without it. evoq starts as a release-boot application before any service's
%% `start/2' runs, so nothing can inject it later. A sibling put two of three
%% fleet nodes into a boot-crash loop this exact way.
-export([store_id/0, data_dir/0]).

info() ->
    #{name => <<"hecate-mail">>,
      version => <<"0.1.0">>,
      description => <<"Async mailboxes for the Macula mesh -- lets an agent delegate work to a citizen who is not online right now">>}.

start(_Opts) -> hecate_mail_sup:start_link().

stop(_State) -> ok.

%% Green once the supervision tree is up. Replace this with a real probe of
%% whatever this service needs in order to do its job. A dark mesh is usually NOT
%% a health failure: decide that deliberately rather than by default.
health() -> ok.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. Other services find this one by these
%% names, so each entry is a promise that something answers.
%%
%% Only three of guide_mailbox_lifecycle's nine commands are reachable over
%% the mesh so far, deliberately: initiate_mailbox, open_mailbox and
%% deposit_letter disclose nothing about a mailbox's contents to call
%% safely with self-asserted identity. mark_letter_read/reply_to_letter/
%% archive_letter/close_mailbox/archive_mailbox/unarchive_mailbox and any
%% future get_mailbox/get_letter query are gated behind resolving whether
%% a macula_response handler gets verified caller identity -- see
%% plans/PLAN_HECATE_MAIL_PART3_MAILBOXES.md's open question. Until then
%% those commands are real, tested domain code (rebar3 eunit exercises
%% them directly) with no RPC surface, not stubs.
capabilities() ->
    [
     #{name => <<"hecate_mail.initiate_mailbox">>, version => 1,
       handler => {initiate_mailbox_responder, []}},
     #{name => <<"hecate_mail.open_mailbox">>, version => 1,
       handler => {open_mailbox_responder, []}},
     #{name => <<"hecate_mail.deposit_letter">>, version => 1,
       handler => {deposit_letter_responder, []}}
    ].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
identity_spec() ->
    #{scope => <<"hecate-mail">>,
      actions => [<<"initiate_mailbox">>, <<"open_mailbox">>, <<"deposit_letter">>],
      resources => [<<"mailboxes/*">>],
      ttl_days => 30}.

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns.
%%
%% ⚠ IT IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another. A generated test compares the two.
-spec store_id() -> atom().
store_id() -> hecate_mail_store.

%% @doc Where it lives on disk.
%%
%% ⚠ DEFAULTS TO A PATH INSIDE THE CONTAINER AND MUST NOT STAY THERE ON A NODE.
%% The fleet keeps application data on its `/bulk' drives and boots from a small
%% eMMC, so `deploy/docker-compose.yml' mounts a volume and sets this. The default
%% is what a laptop wants; a container without the mount loses its record on every
%% recreate, which is the same as not keeping one.
-spec data_dir() -> string().
data_dir() -> chosen(os:getenv("HECATE_DATA_DIR")).

chosen(false) -> "/tmp/hecate_mail";
chosen("") -> "/tmp/hecate_mail";
chosen(Path) -> Path.
