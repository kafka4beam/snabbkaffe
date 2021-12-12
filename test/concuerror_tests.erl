-module(concuerror_tests).

-include("snabbkaffe.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([ race_test/0
        , causality_test/0
        , block_until_multiple_events_test/0
        , block_until_timeout_test/0
        , fail_test/0
        , force_order_test/0
        , force_order_multiple_predicates_test/0
        , force_order_parametrized_test/0
        , force_order_multiple_events_test/0
        ]).

race_test() ->
  ?check_trace(
     begin
       Pid = spawn_link(fun() ->
                            receive
                              {ping, N} ->
                                ?tp(pong, #{winner => N})
                            end
                        end),
       %% Spawn two processes competing to send ping message to the
       %% first one:
       spawn_link(fun() ->
                      ?tp(ping, #{id => 1}),
                      Pid ! {ping, 1},
                      ok
                  end),
       spawn_link(fun() ->
                      ?tp(ping, #{id => 2}),
                      Pid ! {ping, 2},
                      ok
                  end),
       %% Wait for the termination of the receiving process:
       ?block_until(#{?snk_kind := pong}),
       ensure_no_messages()
     end,
     fun(_Ret, Trace) ->
         %% Validate that there's always a pair of events
         ?assertMatch( [{pair, _, _} | _]
                     , ?find_pairs( #{?snk_kind := ping}
                                  , #{?snk_kind := pong}
                                  , Trace
                                  )
                     ),
         %% TODO: I validated manually that value of `winner' field is
         %% indeed nondeterministic, and therefore snabbkaffe doesn't
         %% interfere with concuerror interleavings; however, it would
         %% be nice to check this property automatically as well, but
         %% it requires "testing outside the box":
         %%
         %% Both asserts are true:
         %% ?assertMatch([#{winner := 2}], ?of_kind(pong, Trace)),
         %% ?assertMatch([#{winner := 1}], ?of_kind(pong, Trace)),
         true
     end).

block_until_multiple_events_test() ->
  ?check_trace(
     begin
       spawn(fun() ->
                 ?tp(foo, #{n => 1}),
                 ?tp(foo, #{n => 2})
             end),
       {ok, Sub} = snabbkaffe_collector:subscribe(?match_event(#{?snk_kind := foo}), 2, infinity, infinity),
       ?assertMatch( {ok, [ #{?snk_kind := foo, n := 1}
                          , #{?snk_kind := foo, n := 2}
                          ]}
                   , snabbkaffe_collector:receive_events(Sub)),
       ensure_no_messages()
     end,
     fun(_, Trace) ->
         ?assertMatch( [ #{?snk_kind := foo, n := 1}
                       , #{?snk_kind := foo, n := 2}
                       ]
                     , ?of_kind(foo, Trace)
                     )
     end).

block_until_timeout_test() ->
  ?check_trace(
     begin
       spawn(fun() ->
                 timer:sleep(1000),
                 ?tp(foo, #{})
             end),
       ?block_until(#{?snk_kind := foo}, 100),
       ensure_no_messages()
     end,
     fun(_, _Trace) ->
         true
     end).

causality_test() ->
  ?check_trace(
     begin
       C = spawn(fun() ->
                     receive ping ->
                         ?tp(pong, #{id => c})
                     end
                 end),
       B = spawn(fun() ->
                     receive ping ->
                         ?tp(pong, #{id => b}),
                         C ! ping
                     end
                 end),
       _ = spawn(fun() ->
                     ?tp(pong, #{id => a}),
                     B ! ping
                 end),
       ?block_until(#{?snk_kind := pong, id := c})
     end,
     fun(_, Trace) ->
         ?assertEqual([a,b,c], ?projection(id, ?of_kind(pong, Trace)))
     end).

%% Check that testcases fail gracefully and don't try to do anything
%% that concuerror doesn't understand, like opening files:
fail_test() ->
  try
    ?check_trace(
       begin
         ?tp(foo, #{})
       end,
       fun(_, _) ->
           error(deliberate)
       end)
  catch
    _:_ -> ok
  end.

%% Check that ordering of events is correct when ?force_ordering is used
force_order_test() ->
  ?check_trace(
     begin
       ?force_ordering(#{?snk_kind := first}, #{?snk_kind := second}),
       spawn(fun() ->
                 ?tp(second, #{id => 1})
             end),
       spawn(fun() ->
                 ?tp(second, #{id => 2})
             end),
       timer:sleep(100),
       ?tp(first, #{}),
       [?block_until(#{?snk_kind := second, id := I}) || I <- [1,2]],
       ensure_no_messages()
     end,
     fun(_Result, Trace) ->
         ?assert(?strict_causality(#{?snk_kind := first}, #{?snk_kind := second, id := 1}, Trace)),
         ?assert(?strict_causality(#{?snk_kind := first}, #{?snk_kind := second, id := 2}, Trace))
     end).

%% Check waiting for multiple events
force_order_multiple_predicates_test() ->
  ?check_trace(
     begin
       ?force_ordering(#{?snk_kind := baz}, #{?snk_kind := foo}),
       ?force_ordering(#{?snk_kind := bar}, #{?snk_kind := foo}),
       spawn(fun() ->
                 ?tp(foo, #{})
             end),
       ?tp(bar, #{}),
       ?tp(baz, #{}),
       {ok, _} = ?block_until(#{?snk_kind := foo}),
       ensure_no_messages()
     end,
     fun(_Result, Trace) ->
         ?assert(?strict_causality(#{?snk_kind := bar}, #{?snk_kind := foo}, Trace)),
         ?assert(?strict_causality(#{?snk_kind := baz}, #{?snk_kind := foo}, Trace))
     end).

%% Check parameter bindings in force_ordering
force_order_parametrized_test() ->
  ?check_trace(
     begin
       ?force_ordering( #{?snk_kind := foo, id := _A}
                      , #{?snk_kind := bar, id := _A}
                      ),
       spawn(
         fun() ->
             ?tp(bar, #{id => 1})
         end),
       spawn(
         fun() ->
             ?tp(bar, #{id => 2})
         end),
       timer:sleep(100),
       ?tp(foo, #{id => 1}),
       ?tp(foo, #{id => 2}),
       ?block_until(#{?snk_kind := bar, id := 1}),
       ?block_until(#{?snk_kind := bar, id := 2}),
       ensure_no_messages()
     end,
     fun(_, Trace) ->
         ?assert(?strict_causality( #{?snk_kind := foo, id := _A}
                                  , #{?snk_kind := bar, id := _A}
                                  , Trace
                                  ))
     end).

force_order_multiple_events_test() ->
  ?check_trace(
     begin
       ?force_ordering(#{?snk_kind := foo}, 2, #{?snk_kind := bar}, true),
       spawn(fun() ->
                 ?tp(foo, #{}),
                 ?tp(foo, #{})
             end),
       ?tp(bar, #{}),
       ?block_until(#{?snk_kind := bar})
     end,
     fun(_, Trace) ->
         ?assertMatch( [foo, foo, bar]
                     , ?projection(?snk_kind, ?of_kind([foo, bar], Trace))
                     )
     end).

ensure_no_messages() ->
  receive
    A -> exit({unexpected_message, A})
  after 0 ->
      ok
  end.
