-ifndef(SNABBKAFFE_TRACE_PROD_HRL).
-define(SNABBKAFFE_TRACE_PROD_HRL, true).

-include("common.hrl").

-define(tp(LEVEL, KIND, EVT),
        logger:log(LEVEL,
                   EVT#{ ?snk_kind => KIND
                       , line => ?LINE
                       },
                   #{mfa => {?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY}})).

-define(tp(KIND, EVT), ok).

-define(maybe_crash(KIND, DATA), ok).

-define(maybe_crash(DATA), ok).

-endif.
