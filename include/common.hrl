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

%% Redefining this macro should be impossible, because when snabbkaffe
%% library is compiled with different settings, it would lose the
%% events.
-define(snk_deferred_assert, 'Deferred assertion failed').

-compile(nowarn_update_literal).

-endif.
