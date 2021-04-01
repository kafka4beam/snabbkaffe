-ifndef(SNABBKAFFE_TRACE_HRL).
-define(SNABBKAFFE_TRACE_HRL, true).

-ifdef(TEST).
-ifndef(SNK_COLLECTOR).
-define(SNK_COLLECTOR, true).
-endif. %% SNK_COLLECTOR
-endif. %% TEST

-ifdef(SNK_COLLECTOR).
-include("trace_test.hrl").
-else. %% SNK_COLLECTOR
-include("trace_prod.hrl").
-endif. %% SNK_COLLECTOR

-endif.
