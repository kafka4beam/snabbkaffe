-ifndef(SNABBKAFFE_TRACE_TEST_HRL).
-define(SNABBKAFFE_TRACE_TEST_HRL, true).

-include("common.hrl").

%% Dirty hack: we use reference to a local function as a key that can
%% be used to refer error injection points. This works, because all
%% invokations of this macro create a new fun object with unique id.
-define(__snkStaticUniqueToken, fun() -> ok end).

-define(tp(LEVEL, KIND, EVT),
        snabbkaffe:tp(?__snkStaticUniqueToken, LEVEL, KIND, EVT)).

-define(tp(KIND, EVT), ?tp(debug, KIND, EVT)).

-define(tp_span(KIND, DATA, CODE),
        (fun() ->
             ?tp(KIND, DATA #{?snk_span => start}),
             __SnkRet = CODE,
             ?tp(KIND, DATA #{?snk_span => {complete,  __SnkRet}}),
             __SnkRet
         end)()).

-define(maybe_crash(KIND, DATA),
        snabbkaffe_nemesis:maybe_crash(KIND, DATA#{?snk_kind => KIND})).

-define(maybe_crash(DATA),
        snabbkaffe_nemesis:maybe_crash(?__snkStaticUniqueToken, DATA)).

-endif.
