-module(remote_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("snabbkaffe/include/ct_boilerplate.hrl").

-compile(nowarn_deprecated_function). %% Silence the warnings about slave module

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
  ?check_trace(
     #{timeout => 1000},
     begin
       Remote = start_slave(snkremote),
       ?assertEqual(ok, rpc:call(Remote, remote_funs, remote_tp, [], infinity)),
       Remote
     end,
     fun(Remote, Trace) ->
         ?projection_complete( [node, parent]
                             , ?of_kind('$snabbkaffe_remote_attach', Trace)
                             , [{Remote, node()}]
                             ),
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

t_remote_metadata(Config) when is_list(Config) ->
  Remote = start_slave(snkremote),
  ?check_trace(
     begin
       ?assertEqual(ok, rpc:call(Remote, remote_funs, remote_metadata, [], infinity))
     end,
     fun(_, Trace) ->
         Events = ?of_domain([remote|_], Trace),
         ?assertEqual(Events, ?of_node(Remote, Trace)),
         ?assertMatch([ #{?snk_kind := foo, ?snk_meta := #{ node   := Remote
                                                          , pid    := _
                                                          , gl     := _
                                                          , domain := [remote]
                                                          , meta1  := foo
                                                          , meta2  := bar
                                                          }}
                      , #{?snk_kind := bar, ?snk_meta := #{ node   := Remote
                                                          , pid    := _
                                                          , gl     := _
                                                          , domain := [remote]
                                                          , meta1  := foo
                                                          , meta2  := bar
                                                          }}
                      ], Events)
     end).

t_remote_stats(Config) when is_list(Config) ->
  Remote = start_slave(snkremote),
  ?check_trace(
     begin
       ?assertMatch(ok, rpc:call(Remote, remote_funs, remote_stats, [], infinity))
     end,
     fun(_, _) ->
         ?assertMatch(#{{foo, 1} := [{1, 1}]}, snabbkaffe:get_stats())
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
