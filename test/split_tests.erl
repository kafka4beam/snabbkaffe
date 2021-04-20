-module(split_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe/include/test_macros.hrl").

splitl_test() ->
    Pred = fun is_atom/1,
    ?assertMatch( []
                , snabbkaffe:splitl(Pred, [])
                ),
    L1 = [[a]],
    ?assertMatch( L1
                , snabbkaffe:splitl(Pred, lists:append(L1))
                ),
    L2 = [[a, b, 1], [c, d, 2], [d]],
    ?assertMatch( L2
                , snabbkaffe:splitl(Pred, lists:append(L2))
                ),
    L3 = [[1], [2], [3]],
    ?assertMatch( L3
                , snabbkaffe:splitl(Pred, lists:append(L3))
                ).

splitl_macro_test() ->
  ?assertMatch( [[1, 2, foo], [1, 2, foo]]
              , ?splitl_trace(foo, [1, 2, foo, 1, 2, foo])
              ).

splitr_test() ->
    Pred = fun is_atom/1,
    ?assertMatch( []
                , snabbkaffe:splitr(Pred, [])
                ),
    L1 = [[a]],
    ?assertMatch( L1
                , snabbkaffe:splitr(Pred, lists:append(L1))
                ),
    L2 = [[a, b], [1, c, d], [2, d]],
    ?assertMatch( L2
                , snabbkaffe:splitr(Pred, lists:append(L2))
                ),
    L3 = [[1], [2], [3]],
    ?assertMatch( L3
                , snabbkaffe:splitr(Pred, lists:append(L3))
                ).

splitr_macro_test() ->
  ?assertMatch( [[1, 2], [foo, 1, 2], [foo]]
              , ?splitr_trace(foo, [1, 2, foo, 1, 2, foo])
              ).

split_trace_at_macro_test() ->
  ?assertMatch( {[1, 2], [foo, 1, 2, foo]}
              , ?split_trace_at(foo, [1, 2, foo, 1, 2, foo])
              ).
