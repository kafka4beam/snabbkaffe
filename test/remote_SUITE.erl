-module(remote_SUITE).

-compile(export_all).

-include_lib("snabbkaffe/include/ct_boilerplate.hrl").

%%====================================================================
%% CT callbacks
%%====================================================================

suite() ->
  [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
  snabbkaffe:fix_ct_logging(),
  Config.

end_per_suite(_Config) ->
  ok.

%%====================================================================
%% Testcases
%%====================================================================

t_remote_tp(Config) when is_list(Config) ->
  Remote = start_slave(snkremote),
  ?check_trace(
     #{timeout => 1000},
     begin
       ?assertEqual(ok, rpc:call(Remote, remote_funs, remote_tp, [], infinity))
     end,
     fun(_, Trace) ->
         ?assertMatch( [Remote, Remote]
                     , ?projection(node, ?of_kind([remote_foo, remote_bar], Trace))
                     )
     end).

t_remote_fail(Config) when is_list(Config) ->
  Remote = start_slave(snkremote),
  ?check_trace(
     #{timeout => 1000},
     begin
       ?inject_crash(#{?snk_kind := remote_fail}, snabbkaffe_nemesis:always_crash()),
       ?assertEqual(ok, rpc:call(Remote, remote_funs, remote_crash, [], infinity))
     end,
     fun(_, Trace) ->
         ?assertMatch([_], ?of_kind(snabbkaffe_crash, Trace))
     end).

t_remote_delay(Config) when is_list(Config) ->
  Remote = start_slave(snkremote),
  ?check_trace(
     #{timeout => 1000},
     begin
       ?force_ordering(#{?snk_kind := foo, id := _A}, #{?snk_kind := bar, id := _A}),
       ?assertEqual(ok, rpc:call(Remote, remote_funs, remote_delay, [], infinity)),
       timer:sleep(300),
       ?tp(foo, #{id => 1}),
       ?tp(foo, #{id => 2})
     end,
     fun(_, Trace) ->
         ?assert(?strict_causality( #{?snk_kind := foo, id := _A}
                                  , #{?snk_kind := bar, id := _A}
                                  , Trace
                                  )),
         ?projection_complete(id, ?of_kind(bar, Trace), [1, 2])
     end).

%%====================================================================
%% Internal functions
%%====================================================================

start_slave(Name) ->
  {ok, Host} = inet:gethostname(),
  Remote = list_to_atom(lists:concat([Name, "@", Host])),
  ct_slave:start(Name, [{monitor_master, true}]),
  rpc:call(Remote, code, add_pathsz, [code:get_path()]),
  snabbkaffe:forward_trace(Remote),
  Remote.
