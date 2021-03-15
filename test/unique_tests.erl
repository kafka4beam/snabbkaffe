-module(unique_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe.hrl").

-define(meta(TS), ?snk_meta => #{time => TS}).

-define(valid(L),
        ?assertMatch(true, snabbkaffe:unique(L))).

-define(invalid(L),
        ?assertError( {panic, #{?snk_kind := "Duplicate elements found"}}
                    , snabbkaffe:unique(L)
                    )).

unique_succ_test() ->
  ?valid([]),
  ?valid([ #{foo => 1, ?meta(1)}
         , #{bar => 1, ?meta(2)}
         , #{bar => 2, ?meta(2)}
         ]).

unique_fail_test() ->
  ?invalid([ #{foo => 1, ?meta(1)}
           , #{bar => 1, ?meta(2)}
           , #{foo => 1, ?meta(2)}
           ]).
