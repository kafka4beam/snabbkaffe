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

%% TODO: I don't like the overhead of having a fun here in the prod
%% mode, but removing it can change the semantics of the program in
%% prod and test builds.
-define(tp_span(KIND, DATA, CODE),
        (fun() ->
             ?tp(KIND, DATA #{?snk_span => start}),
             __SnkRet = begin CODE end,
             ?tp(KIND, DATA #{?snk_span => {complete,  __SnkRet}}),
             __SnkRet
         end)()).

-endif.
