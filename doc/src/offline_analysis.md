Offline analysis of the traces
==============================

Snabbkaffe trace is a regular list, so any pure function or a list comprehension can be used to analyze it.
Nonetheless, it comes with a few predefined macros and functions for trace analysis.

# Event correlations

## ?strict_causality

`?strict_causality` macro is very powerful.
It finds pairs of events matching "cause" and "effect" patterns, and verifies that each for each cause there is an effect, and vice versa.

For example, the following test verifies that every received message eventually gets processed:

```erlang
-module(offline_analysis_example).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("eunit/include/eunit.hrl").

strict_causality_test() ->
  Trace = [#{?snk_kind => msg_received,  id => 1},
           #{?snk_kind => msg_received,  id => 2},
           #{?snk_kind => unrelated_event},
           #{?snk_kind => msg_processed, id => 2},
           #{?snk_kind => msg_received,  id => 3},
           #{?snk_kind => msg_processed, id => 3},
           #{?snk_kind => msg_processed, id => 1}
          ],
  ?assert(
    ?strict_causality(#{?snk_kind := msg_received,  id := _Id}, %% Match cause
                      #{?snk_kind := msg_processed, id := _Id}, %% Match event
                      Trace)).
```

There is an extended version of the macro that allows to extend pattern matching with a guard expression, that can contain arbitrary code:

Suppose we’re testing a “integer_to_list server”.
The following code is all that is needed to express the property
"every request containing a certain number should be eventually replied with the number converted to the list":

```erlang
to_string_server_test() ->
  ExampleTrace = [#{request => 1},
                  #{reply   => "1"},
                  #{request => 4},
                  #{request => 4},
                  #{reply   => "4"},
                  #{reply   => "4"}],
  ?assert(
    ?strict_causality(#{request := _Req},                %% Match cause
                      #{reply := _Resp},                 %% Match effect
                      _Resp =:= integer_to_list(_Req),   %% Guard
                      ExampleTrace)).
```

The return value of both macros is:
- `true` when pairs of events were found.
- `false` when the macro didn't find any matching events (neither causes nor effects).
- An exception is thrown when there are unmatched causes or effects.
It is recommended to wrap this macro in an `?assert` to verify that it actually matched the pairs of events.

A few notes on the variable binding inside `?strict_causality`-like macros:
- Variable bindings from outside of the macro are propagated into the match expression, e.g.
  ```erlang
  Id = 2,
  ?strict_causality(#{req := Id}, ...)
  ```
  will only match events with `req := 2`.
- Variable bindings from the "cause" match expression are propagated to the "effect" match expression.
- Variable bindings from both "cause" and "effect" expressions are propagated to the guard expression.

## ?causality

`?causality` macros work similarly to `?strict_causality`, except they allow unmatched causes.
For example, they can be used in the situations where some message loss is allowed.

## ?find_pairs

`?find_pairs` is a macro that works similarly to `?strict_causality`, except it returns the list of pairs and unmatched causes and effects:

```erlang
find_pairs_test() ->
  ExampleTrace = [#{request => 1},
                  #{reply   => "1"},
                  #{request => 4},
                  #{request => 4},
                  #{reply   => "4"},
                  #{reply   => "5"}],
  ?assertMatch(
    [{pair, #{request := 1}, #{reply := "1"}},
     {pair, #{request := 4}, #{reply := "4"}},
     {unmatched_cause, #{request := 4}},
     {unmatched_effect, #{reply := "5"}}
    ],
    ?find_pairs(#{request := _Req},                %% Match cause
                #{reply := _Resp},                 %% Match effect
                _Resp =:= integer_to_list(_Req),   %% Guard
                ExampleTrace)).
```

A simple version without the guard is present too.

## ?pair_max_depth

`?pair_max_depth` macro takes a list of pairs produced by `?find_pairs` macro and returns maximum nesting level of pairs.
Its usecase is verification of overload protection routines.
Suppose the system has a load limiter that prevents it from running more than N parallel tasks.
`?pair_max_depth` helps verifying this property.

## strictly_increasing

`snabbkaffe:strictly_increasing(List)` function verifies `A > B > C > ...` relation holds for all elements of the list:

```erlang
strictly_increasing_test() ->
  ?assert(snabbkaffe:strictly_increasing([1, 2, 5, 6])),
  ?assertNot(snabbkaffe:strictly_increasing([])),
  ?assertError(_, snabbkaffe:strictly_increasing([1, 2, 2, 3])).
```

It returns `true` when the list is not empty and the elements of the list are increasing,
`false` when the list is empty,
and throws an exception when the property is violated.

## increasing

`snabbkaffe:increasing(List)` function is similar to `strictly_increasing`, except it checks `>=` property.

# Filtering events

## ?of_kind

This macro extracts events of certain kind or kinds:

```erlang
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

`?split_trace_at` macro splits the trace into two parts: before and after the first occurrence of an event matching a pattern:

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

This macro is useful when the SUT changes state in some way, and its behavior is dependent on the state.
The SUT should a emit an event indicating the state change.
This event can be used in the check stage to split the trace in two parts, that can be analysed by two different rules.

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

`?projection` macro simplifies processing of the events by extracting values of their fields.
It can extract one or multiple fields from the event:

```erlang
projection_single_field_test() ->
  Trace = [#{?snk_kind => foo, field1 => 1},
           #{?snk_kind => foo, field1 => 2}],
  ?assertMatch([1, 2],
               ?projection(field1, Trace)).
```

```erlang
projection_test() ->
  Trace = [#{?snk_kind => foo, field1 => 1},
           #{?snk_kind => foo, field1 => 2}],
  ?assertMatch([{foo, 1}, {foo, 2}],
               ?projection([?snk_kind, field1], Trace)).
```

# Misc. functions

## ?give_or_take

`?give_or_take` macro can be used for approximate matching of numeric values:

```erlang
?give_or_take(_Expected = 20, _Deviation = 2, Value)
```
