-ifndef(SNABBKAFFE_TRACE_HRL).
-define(SNABBKAFFE_TRACE_HRL, true).

-ifndef(SNK_COLLECTOR).
  -ifdef(TEST).
    -define(SNK_COLLECTOR, true).
  -else.
    -define(SNK_COLLECTOR, false).
  -endif.
-endif.

-if(?SNK_COLLECTOR == true).
  -include("trace_test.hrl").
-elif(?SNK_COLLECTOR == false).
  -include("trace_prod.hrl").
-else.
  -error("SNK_COLLECTOR macro should be defined as either true or false").
-endif.

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


%% TODO: I don't like the overhead of having a fun here in the prod
%% mode, but removing it can change the semantics of the program in
%% prod and test builds.
-define(tp_span(SEVERITY, KIND, DATA, CODE),
        (fun() ->
             ?tp(SEVERITY, KIND, DATA #{?snk_span => start}),
             __SnkRet = begin CODE end,
             ?tp(SEVERITY, KIND, DATA #{?snk_span => {complete,  __SnkRet}}),
             __SnkRet
         end)()).

-endif.
