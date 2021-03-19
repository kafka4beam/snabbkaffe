-ifndef(SNK_COLLECTOR).
-define(SNK_COLLECTOR, true).
-endif.

-include("snabbkaffe.hrl").

-ifdef(CONCUERROR).
-define(SNK_CONCUERROR, true).
-else.
-define(SNK_CONCUERROR, false).
-endif.

-ifdef(OTP_RELEASE).
-define(BIND_STACKTRACE(V), : V).
-define(GET_STACKTRACE(V), ok).
-else.
-define(BIND_STACKTRACE(V),).
-define(GET_STACKTRACE(V), V = erlang:get_stacktrace()).
-endif.

-define(PT_TP_FUN, snabbkaffe_tp_fun).
-define(PT_REMOTE, snabbkaffe_remote).
