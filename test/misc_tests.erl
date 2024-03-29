-module(misc_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe.hrl").

-define(foo(A), #{foo => A, bar => bar, baz => baz}).

tp_printouts_test() ->
  ?check_trace(
     begin
       ?tp(warning, "This is a warning tracepoint",
           #{ key1 => value1
            , key2 => "Value 2"
            }),
       ?tp(notice, "This is a notice tracepoint",
           #{ key1 => value1
            , key2 => "Value 2"
            })
     end,
     fun(_, _) ->
         true
     end).

projection_1_test() ->
  ?assertMatch( [1, 2, 3]
              , snabbkaffe:projection( foo
                                     , [?foo(1), ?foo(2), ?foo(3)]
                                     )).

projection_2_test() ->
  ?assertMatch( [{1, bar}, {2, bar}, {3, bar}]
              , snabbkaffe:projection( [foo, bar]
                                     , [?foo(1), ?foo(2), ?foo(3)]
                                     )).

strictly_increasing_test() ->
  ?assertNot(snabbkaffe:strictly_increasing([])),
  ?assert(snabbkaffe:strictly_increasing([1])),
  ?assert(snabbkaffe:strictly_increasing([1, 2, 5, 6])),
  ?assertError(_, snabbkaffe:strictly_increasing([1, 2, 5, 3])),
  ?assertError(_, snabbkaffe:strictly_increasing([1, 2, 2, 3])).

increasing_test() ->
  ?assertNot(snabbkaffe:increasing([])),
  ?assert(snabbkaffe:increasing([1])),
  ?assert(snabbkaffe:increasing([1, 2, 5, 6])),
  ?assert(snabbkaffe:increasing([1, 2, 2, 3])),
  ?assertError(_, snabbkaffe:increasing([1, 2, 5, 3])).

get_cfg_test() ->
  Cfg1 = [{proper, [ {numtests, 1000}
                   , {timeout, 42}
                   ]}
         ],
  Cfg2 = #{ proper => #{ numtests => 1000
                       , timeout => 42
                       }
          },
  Cfg3 = [{proper, #{ numtests => 1000
                    , timeout => 42
                    }
          }],
  ?assertMatch(42, snabbkaffe:get_cfg([proper, timeout], Cfg1, 10)),
  ?assertMatch(42, snabbkaffe:get_cfg([proper, foo], Cfg1, 42)),
  ?assertMatch(42, snabbkaffe:get_cfg([proper, timeout], Cfg2, 10)),
  ?assertMatch(42, snabbkaffe:get_cfg([proper, foo], Cfg2, 42)),
  ?assertMatch(42, snabbkaffe:get_cfg([proper, timeout], Cfg3, 10)),
  ?assertMatch(42, snabbkaffe:get_cfg([proper, foo], Cfg3, 42)).

tp_without_collector_test() ->
  snabbkaffe:stop(),
  undefined = whereis(snabbkaffe_collector),
  %% Test that ?tp macro works without starting the local collector
  ?tp(foo, #{}).
