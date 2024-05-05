-ifndef(SNABBKAFFE_HRL).
-define(SNABBKAFFE_HRL, true).

-include("trace.hrl").
-include("test_macros.hrl").

-define(defer_assert(BODY),
        (fun() ->
             try BODY
             catch
               EC:Err:Stack ->
                 ?tp(error, ?snk_deferred_assert, #{EC => Err, stacktrace => Stack})
             end,
             ok
         end)()).

-endif.
