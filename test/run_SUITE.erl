-module(run_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("stdlib/include/assert.hrl").
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

init_per_group(_GroupName, Config) ->
  Config.

end_per_group(_GroupName, _Config) ->
  ok.

groups() ->
  [].

%%====================================================================
%% Testcases
%%====================================================================

t_multiple_props_success(Cfg) when is_list(Cfg) ->
  ?check_trace(
     1,
     [ fun check_ok/1
     , fun check_true/1
     , fun check_ok/2
     , fun check_true/2
     , {"foo", fun check_ok/1}
     , {"foo", fun check_true/1}
     , {"foo", fun check_ok/2}
     , {"foo", fun check_true/2}
     ]).

t_multiple_props_error(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       1,
       [ fun check_ok/1
       , fun check_error/1
       , {"foo", fun check_ok/1}
       , {"foo", fun check_true/2}
       ])).

t_multiple_props_false(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       1,
       [ fun check_ok/1
       , fun check_false/2
       , {"foo", fun check_ok/1}
       , {"foo", fun check_true/2}
       ])).

t_multiple_props_exit(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       1,
       [ fun check_ok/1
       , {"foo", fun check_exit/2}
       , {"foo", fun check_ok/1}
       , {"foo", fun check_true/2}
       ])).

t_multiple_fprop_throw(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       1,
       [ fun check_ok/1
       , {"foo", fun check_throw/2}
       , {"foo", fun check_ok/1}
       , {"foo", fun check_true/2}
       ])).

t_run_stage_error(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       error(fail),
       fun check_true/1
       )).

t_run_stage_exit(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       exit(fail),
       fun check_true/1
       )).

t_run_stage_throw(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  ?assertError(
     _,
     ?check_trace(
       exit(fail),
       fun check_true/1
       )).

t_silence_interval_timetrap(Cfg) when is_list(Cfg) ->
  logger:notice("Don't mind the below crashes, they are intentional!", []),
  {_, Ref} =
    spawn_monitor(
      fun() ->
          ?check_trace(
             #{timetrap => 1000, timeout => 100},
             begin
               timer:apply_interval(10, ?MODULE, do_trace, [])
             end,
             fun check_true/1
            )
      end),
  receive
    {'DOWN', Ref, _, _, timetrap} ->
      ok
  after 1200 ->
      error(no_timetrap)
  end.

t_pretty_print(Cfg) when is_list(Cfg) ->
  snabbkaffe:start_trace(),
  ?tp(test_event, #{foo => bar}),
  ?tp(test_event2, #{foo => bar}),
  Trace = snabbkaffe:collect_trace(),
  snabbkaffe:dump_trace(Trace).

%%====================================================================
%% Internal functions
%%====================================================================

do_trace() ->
  ?tp(blah, #{}).

check_ok(_Ret, _Trace) ->
  ok.

check_ok(_Trace) ->
  ok.

check_true(_Ret, _Trace) ->
  true.

check_true(_Trace) ->
  true.

check_false(_Trace, _Ret) ->
  false.

check_error(_Ret) ->
  error(fail).

check_exit(_Trace, _Ret) ->
  exit(fail).

check_throw(_Trace, _Ret) ->
  throw(fail).
