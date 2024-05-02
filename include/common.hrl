-ifndef(SNABBKAFFE_COMMON_HRL).
-define(SNABBKAFFE_COMMON_HRL, true).

-ifndef(snk_kind).
-define(snk_kind, '$kind'). %% "$" will make kind field go first when maps are printed.
-endif.

-ifndef(snk_meta).
-define(snk_meta, '~meta'). %% "~" will make meta field go last when maps are printed.
-endif.

-ifndef(snk_span).
-define(snk_span, '$span').
-endif.

-ifndef(snk_deferred_assert).
-define(snk_deferred_assert, 'Assertion failed').
-endif.

-endif.
