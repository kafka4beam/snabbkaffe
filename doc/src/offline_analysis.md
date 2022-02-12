Offline analysis of the traces
==============================

Snabbkaffe trace is a regular list, so any pure function or a list comprehension can be used to analyze it.
Nonetheless, it comes with a few predefined macros and functions for trace analysis.

# Filtering events

## ?of_kind

This macro extracts events of certain kind or kinds:

```erlang
-module(offline_analysis_example).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("eunit/include/eunit.hrl").

of_kind_test() ->
    Trace = [#{?snk_kind => foo}, #{?snk_kind => bar}],
    ?assertMatch([#{?snk_kind := foo}], ?of_kind(foo, Trace)),
    ?assertMatch([#{?snk_kind := foo}, #{?snk_kind := bar}], ?of_kind([foo, bar], Trace)).
```

## ?of_domain

`?of_domain` macro extracts events that were produced from processes with a specified logger domain.
It supports match expressions, e.g.:

```erlang
of_domain_test() ->
   ?check_trace(
     begin
       logger:update_process_metadata(#{domain => [my, domain]}),
       ?tp(foo, #{})
     end,
     fun(Trace) ->
       ?assertMatch([#{?snk_kind := foo}],
                    ?of_domain([my|_], Trace))
     end).
```

## ?of_node

`?of_node` macro extracts events that were produced on the specified node:

```erlang
of_node_test() ->
   ?check_trace(
     begin
       ?tp(foo, #{})
     end,
     fun(Trace) ->
       ThisNode = node(),
       ?assertMatch([#{?snk_kind := foo}],
                    ?of_node(ThisNode, Trace))
     end).
```

# Splitting traces

## ?split_trace_at

`?split_trace_at` macro splits the trace into two parts: before and after of the first occurrence of an event matching a pattern:

```erlang
split_trace_at_test() ->
  Trace = [#{?snk_kind => foo},
           #{?snk_kind => bar},
           #{?snk_kind => baz},
           #{?snk_kind => quux},
           #{?snk_kind => baz}
          ],
  ?assertMatch( {[#{?snk_kind := foo}, #{?snk_kind := bar}], [#{?snk_kind := baz}|_]}
              , ?split_trace_at(#{?snk_kind := baz}, Trace)
              ).
```

## ?splitl_trace

`?splitr_trace` macro splits the list into multiple lists, where each sublist ends with an element that matches the pattern:

```erlang
splitl_macro_test() ->
  Trace = [1, 2, foo, 3, 4, foo],
  ?assertMatch( [[1, 2, foo], [3, 4, foo]]
              , ?splitl_trace(foo, Trace)
              ).
```

## ?splitr_trace

`?splitr_trace` macro splits the list into multiple lists, where each sublist begins from an element that matches the pattern:

```erlang
splitr_macro_test() ->
  Trace = [1, 2, foo, 3, 4, foo],
  ?assertMatch( [[1, 2], [foo, 3, 4], [foo]]
              , ?splitr_trace(E when is_atom(E), Trace)
              ).
```

# Transforming events

## ?projection

# Analyzing pairs of events

## ?strict_causality

## ?causality

## ?find_pairs

## ?pair_max_depth
