-ifndef(SNABBKAFFE_TRACE_PROD_HRL).
-define(SNABBKAFFE_TRACE_PROD_HRL, true).

-include("common.hrl").

-define(tp(LEVEL, KIND, EVT),
        logger:log(LEVEL,
                   EVT#{ ?snk_kind => KIND },
                   #{ mfa => {?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY}
                    , line => ?LINE
                    , file => ?FILE
                    })).

-define(tp(KIND, EVT),
        begin
          _ = EVT,
          ok
        end).

-define(maybe_crash(KIND, DATA), ok).

-define(maybe_crash(DATA), ok).

-endif.
