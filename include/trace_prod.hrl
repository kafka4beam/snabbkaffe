-ifndef(SNABBKAFFE_TRACE_PROD_HRL).
-define(SNABBKAFFE_TRACE_PROD_HRL, true).

-include("common.hrl").

-ifndef(SNK_PROD_KIND).
-define(SNK_PROD_KIND, ?snk_kind).
-endif.

-define(tp(LEVEL, KIND, EVT),
        logger:log(LEVEL,
                   EVT#{ ?SNK_PROD_KIND => KIND },
                   #{ mfa => {?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY}
                    , line => ?LINE
                    , file => ?FILE
                    })).

-define(tp(KIND, EVT),
        begin
          _ = EVT,
          ok
        end).

-define(tp_ignore_side_effects_in_prod(_KIND, _EVT), ok).

-define(maybe_crash(KIND, DATA), ok).

-define(maybe_crash(DATA), ok).

-endif.
