%% @doc The service contract, asserted locally.
%%
%% hecate_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(hecate_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes hecate_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots hecate_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(hecate_mail_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, hecate_mail).
-define(SERVICE, hecate_mail_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If hecate_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"hecate-mail">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

health_is_green_test() ->
    ?assertEqual(ok, ?SERVICE:health()).

%% An empty list is the correct answer for a service that does nothing yet. The
%% assertion is here so that adding a capability breaks a test and makes someone
%% write down what the service can now actually do.
announces_no_capability_yet_test() ->
    ?assertEqual([], ?SERVICE:capabilities()).

identity_spec_has_the_shape_hecate_om_expects_test() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_list(Actions)),
    ?assert(is_list(Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%% A resource this service is not authorised for is a publish the realm would
%% refuse once UCAN delegation lands. Asking for nothing and claiming nothing
%% must stay in step, so the two are asserted together.
authority_matches_what_is_announced_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([], ?SERVICE:capabilities()),
    ?assertEqual([], Actions),
    ?assertEqual([], Resources).

%% The supervisor starts and stops cleanly on its own, without hecate_om. It has
%% no children as generated; this asserts the tree is startable, not that it does
%% any work.
supervisor_starts_and_stops_test() ->
    {ok, Pid} = hecate_mail_sup:start_link(),
    ?assert(is_process_alive(Pid)),
    ?assertEqual([], supervisor:which_children(Pid)),
    unlink(Pid),
    exit(Pid, shutdown).

%%==============================================================================
%% The config the store cannot boot without
%%==============================================================================

%% ⚠ A SIBLING SERVICE'S FLEET CRASH-LOOPED ON TWO OF THREE NODES FOR WANT OF THE
%% `evoq' BLOCK.
%%
%% Exporting `store_id/0' makes `hecate_om:boot/1' start the store AND a per-store
%% evoq subscription. That subscription reads through evoq, which raises
%% `{not_configured, event_store_adapter}' unless sys.config names the adapter,
%% and evoq starts as a release-boot application before any service's `start/2'
%% runs, so nothing can inject it later.
%%
%% This reads the shipped config template, because the failure is a MISSING BLOCK
%% and no amount of exercising the code can notice something that is not there.
%% It compares the Erlang side of a boundary against the config side, which is
%% what neither side's own tests can do.
the_evoq_adapter_is_configured_wherever_a_store_is_opened_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assert(erlang:function_exported(?SERVICE, store_id, 0)),
    lists:foreach(
      fun(Needed) ->
              ?assertNotEqual(nomatch, binary:match(Text, Needed),
                              {missing_from_sys_config, Needed})
      end,
      [<<"{evoq,">>, <<"event_store_adapter">>, <<"subscription_adapter">>,
       <<"reckon_evoq_adapter">>]).

%% ⚠ AND THE STORE ID IS IN TWO PLACES, WHICH IS ONE MORE THAN IT SHOULD BE.
%% `store_id/0' is what hecate_om opens; the `{store_id, ...}' in the evoq block
%% is what evoq falls back to when it resolves a dispatch before knowing there is
%% none. Nothing makes them agree, and disagreeing opens one store and addresses
%% another. Same boundary guard, other side.
the_store_id_agrees_between_erlang_and_config_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Declared = atom_to_binary(?SERVICE:store_id(), utf8),
    ?assertNotEqual(nomatch, binary:match(Text, Declared),
                    {store_id_not_in_sys_config, Declared}).

%% The data directory must be somewhere, and a laptop default is fine. What is
%% not fine is shipping that default to a node, which is why the generated
%% compose file mounts a volume and sets the variable this reads.
the_data_directory_is_answerable_test() ->
    ?assert(erlang:function_exported(?SERVICE, data_dir, 0)),
    ?assert(is_list(?SERVICE:data_dir())),
    ?assertNotEqual("", ?SERVICE:data_dir()).
%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Image = pinned("Containerfile", "FROM docker.io/erlang:([0-9]+)"),
    Ci = pinned(".github/workflows/lint.yml", "image: erlang:([0-9]+)"),
    Running = list_to_binary(erlang:system_info(otp_release)),
    %% Sorted and deduplicated, so a failure prints all three rather than the
    %% first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, Ci, Running])).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [{capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
