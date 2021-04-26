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
