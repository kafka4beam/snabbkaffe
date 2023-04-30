-module(prod_log_test).

-include_lib("eunit/include/eunit.hrl").

-undef(TEST).
-include("trace.hrl").

trace_prod_test() ->
  ?tp(my_kind, #{foo => 1, bar => 2}),
  ?tp(info, my_kind, #{foo => 1, bar => 2}),
  ?tp(notice, my_kind, #{foo => 1, bar => 2}),
  ?tp(notice, "My kind", #{foo => 1, bar => 2}),
  ?tp_span(notice, my_span, #{foo => 1, bar => 1},
           begin
             40 + 2
           end).

no_unused_variables_test() ->
  A = 1, %% This variable should not be recognized as unused
  ?tp(foo, #{a => A}).

tp_ignore_side_effects_in_prod_test() ->
  %% Should not evaluate its args at all when in prod.
  ?tp_ignore_side_effects_in_prod(foo, #{look => error(boom)}).
