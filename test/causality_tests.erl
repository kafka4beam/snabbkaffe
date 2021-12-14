-module(causality_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe.hrl").

%% Pairs No Guards
-define(PNG(Trace),
        ?find_pairs( #{foo := _A}, #{bar := _A}
                   , Trace
                   )).

%% Pairs With Guard
-define(PWG(Trace),
        ?find_pairs( #{foo := _A}, #{bar := _B}, _A + 1 =:= _B
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
-define(unmatched_cause(A), {unmatched_cause, #{foo := A}}).
-define(unmatched_effect(A), {unmatched_effect, #{bar := A}}).

-define(error_msg, "Effect occurs before cause").

-define(error_msg_cause, "Causality violation").

png_success_test() ->
  ?assertMatch( []
              , ?PNG([])
              ),
  ?assertMatch( []
              , ?PNG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( [?pair(1), ?pair(owo)]
              , ?PNG([?foo(1), ?foo(owo), foo, ?bar(owo), ?bar(1), bar])
              ),
  ?assertMatch( [?unmatched_cause(1), ?pair(2)]
              , ?PNG([?foo(1), ?foo(2), foo, ?bar(2), bar])
              ),
  ?assertMatch( [?unmatched_cause(1), ?pair(2), ?pair(owo)]
              , ?PNG([?foo(1), ?foo(2), ?bar(2), ?foo(owo), ?bar(owo)])
              ),
  ?assertMatch( [ ?unmatched_cause(1), ?unmatched_effect(owo)
                , ?unmatched_cause(owo), ?pair(2), ?unmatched_effect(44)
                ]
              , ?PNG([ ?foo(1), ?bar(owo), ?foo(owo), ?foo(2)
                     , foo, ?bar(2), ?bar(44)
                     ])
              ).

spng_unmatched_effect_test() ->
  ?assertMatch( [?pair(1), ?unmatched_effect(owo), ?unmatched_cause(owo)]
              , ?PNG([?foo(1), ?bar(owo), foo, ?foo(owo), ?bar(1), bar])
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

png_scoped_test() ->
  %% Test that match specs in ?find_pairs capture variables from the
  %% context:
  _A = owo,
  ?assertMatch( [?pair(owo)]
              , ?PNG([?foo(1), ?foo(owo), foo, ?bar(owo), ?bar(1), bar])
              ).

-define(pair_inc(A), {pair, #{foo := A}, #{bar := A + 1}}).

pwg_success_test() ->
  ?assertMatch( []
              , ?PWG([])
              ),
  ?assertMatch( []
              , ?PWG([#{quux => 1}, #{quux => 2}])
              ),
  ?assertMatch( [?pair_inc(1), ?pair_inc(2)]
              , ?PWG([?foo(1), foo, ?foo(2), ?bar(2), ?bar(3)])
              ),
  ?assertMatch( [?unmatched_cause(1), ?pair_inc(2)]
              , ?PWG([?foo(1), ?foo(2), foo, ?bar(3), bar])
              ).

pwg_unmatched_test() ->
  ?assertMatch( [?unmatched_cause(2), ?unmatched_effect(1)]
              , ?PWG([?foo(2), ?bar(1)])
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
