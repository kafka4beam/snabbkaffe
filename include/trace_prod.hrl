-ifndef(SNABBKAFFE_TRACE_PROD_HRL).
-define(SNABBKAFFE_TRACE_PROD_HRL, true).

-include("common.hrl").

%% TODO: I don't like the overhead of having a fun here, but removing
%% it can change the semantics of the progrom in prod and test builds.
-define(tp_span(KIND, DATA, CODE),
        (fun() ->
             CODE
         end)()).

-define(tp(LEVEL, KIND, EVT),
        logger:log(LEVEL, EVT#{ ?snk_kind => KIND
                              , mfa => {?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY}
                              , line => ?LINE
                              })).

-define(tp(KIND, EVT), ok).

-define(maybe_crash(KIND, DATA), ok).

-define(maybe_crash(DATA), ok).

-endif.
