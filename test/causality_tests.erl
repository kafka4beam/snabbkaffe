-module(causality_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe.hrl").

%% Strict Pairs No Guards
-define(SPNG(Trace),
        ?find_pairs( true
                   , #{foo := _A}, #{bar := _A}
                   , Trace
                   )).

%% Fuzzy Pairs No Guards
-define(FPNG(Trace),
        ?find_pairs( false
                   , #{foo := _A}, #{bar := _A}
                   , Trace
                   )).

%% Strict Pairs With Guard
-define(SPWG(Trace),
        ?find_pairs( true
                   , #{foo := _A}, #{bar := _B}, _A + 1 =:= _B
                   , Trace
                   )).

%% Strict Cuasality No Guard
-define(SCNG(Trace),
        ?strict_causality( #{foo := _A} when true, #{bar := _A} when true
                         , Trace
                         )).

%% Weak Cuasality No Guard
-define(WCNG(Trace),
        ?causality( #{foo := _A}, #{bar := _A}
                  , Trace
                  )).

%% Weak Cuasality With Guard
-define(WCWG(Trace),
        ?causality( #{foo := _A}, #{bar := _B}, _A + 1 =:= _B
                  , Trace
                  )).

-define(foo(A), #{foo => A}).
-define(bar(A), #{bar => A}).

-define(pair(A), {pair, #{foo := A}, #{bar := A}}).
-define(singleton(A), {singleton, #{foo := A}}).

-define(error_msg, "Effect occurs before cause").

-define(error_msg_cause, "Cause without effect").

spng_success_test() ->
  ?assertMatch( []
              , ?SPNG([])
              ),
  ?assertMatch( []
              , ?SPNG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( [?pair(1), ?pair(owo)]
              , ?SPNG([?foo(1), ?foo(owo), foo, ?bar(owo), ?bar(1), bar])
              ),
  ?assertMatch( [?singleton(1), ?pair(2)]
              , ?SPNG([?foo(1), ?foo(2), foo, ?bar(2), bar])
              ),
  ?assertMatch( [?singleton(1), ?pair(2), ?pair(owo)]
              , ?SPNG([?foo(1), ?foo(2), ?bar(2), ?foo(owo), ?bar(owo)])
              ).

spng_fail_test() ->
  ?assertError( {panic, #{?snk_kind := ?error_msg}}
              , ?SPNG([?foo(1), ?bar(owo), foo, ?foo(owo), ?bar(1), bar])
              ).

fpng_success_test() ->
  ?assertMatch( []
              , ?FPNG([])
              ),
  ?assertMatch( []
              , ?FPNG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( [?pair(1), ?pair(owo)]
              , ?FPNG([?foo(1), ?foo(owo), foo, ?bar(owo), ?bar(1), bar])
              ),
  ?assertMatch( [?singleton(1), ?pair(2)]
              , ?FPNG([?foo(1), ?foo(2), foo, ?bar(2), bar])
              ),
  ?assertMatch( [?singleton(1), ?pair(2), ?pair(owo)]
              , ?FPNG([?foo(1), ?foo(2), ?bar(2), ?foo(owo), ?bar(owo)])
              ),
  ?assertMatch( [?singleton(1), ?singleton(owo), ?pair(2)]
              , ?FPNG([ ?foo(1), ?bar(owo), ?foo(owo), ?foo(2)
                      , foo, ?bar(2), ?bar(44)
                      ])
              ).

wcwg_succ_test() ->
  ?assertMatch( false
              , ?WCWG([])
              ),
  ?assertMatch( true
              , ?WCWG([?foo(1)])
              ),
  ?assertMatch( true
              , ?WCWG([?foo(1), ?bar(2)])
              ).

wcwg_fail_test() ->
  ?assertError( {panic, _}
              , ?WCWG([?foo(3), ?bar(1)])
              ),
  ?assertError( {panic, _}
              , ?WCWG([?foo(2), ?bar(1)])
              ).

fpng_scoped_test() ->
  %% Test that match specs in ?find_pairs capture variables from the
  %% context:
  _A = owo,
  ?assertMatch( [?pair(owo)]
              , ?FPNG([?foo(1), ?foo(owo), foo, ?bar(owo), ?bar(1), bar])
              ).

-define(pair_inc(A), {pair, #{foo := A}, #{bar := A + 1}}).

spwg_success_test() ->
  ?assertMatch( []
              , ?SPWG([])
              ),
  ?assertMatch( []
              , ?SPWG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( [?pair_inc(1), ?pair_inc(2)]
              , ?SPWG([?foo(1), foo, ?foo(2), ?bar(2), ?bar(3)])
              ),
  ?assertMatch( [?singleton(1), ?pair_inc(2)]
              , ?SPWG([?foo(1), ?foo(2), foo, ?bar(3), bar])
              ).

spwg_fail_test() ->
  ?assertError( {panic, _}
              , ?SPWG([?foo(2), ?bar(1)])
              ).

scng_succ_test() ->
  ?assertMatch( false
              , ?SCNG([])
              ),
  ?assertMatch( false
              , ?SCNG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( true
              , ?SCNG([?foo(1), ?foo(2), foo, ?bar(2), ?bar(1)])
              ).

scng_fail_test() ->
  ?assertError( {panic, #{?snk_kind := ?error_msg_cause}}
              , ?SCNG([?foo(1), foo])
              ).

wcng_succ_test() ->
  ?assertMatch( false
              , ?WCNG([])
              ),
  ?assertMatch( false
              , ?WCNG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( true
              , ?WCNG([?foo(1), ?foo(2), foo, ?bar(2)])
              ).
