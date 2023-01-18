-ifndef(SNABBKAFFE_TRACE_TEST_HRL).
-define(SNABBKAFFE_TRACE_TEST_HRL, true).

-include("common.hrl").

%% Dirty hack: we use reference to a local function as a key that can
%% be used to refer error injection points. This works, because all
%% invokations of this macro create a new fun object with unique id.
%%
%% Note: the returned tuple doesn't play any role for snabbkaffe,
%% since it compares fun objects rather than return values.
%%
%% But it's used for pretty printing of the trace dump.
-define(__snkStaticUniqueToken, fun() -> {?FILE, ?LINE} end).

-define(tp(LEVEL, KIND, EVT),
        snabbkaffe:tp(?__snkStaticUniqueToken, LEVEL, KIND, EVT)).

-define(tp(KIND, EVT), ?tp(debug, KIND, EVT)).

-define(maybe_crash(KIND, DATA),
        snabbkaffe_nemesis:maybe_crash(KIND, DATA#{?snk_kind => KIND})).

-define(maybe_crash(DATA),
        snabbkaffe_nemesis:maybe_crash(?__snkStaticUniqueToken, DATA)).

-endif.
