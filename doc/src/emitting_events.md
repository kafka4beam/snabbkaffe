# Emitting events

Snabbkaffe requires to instrument the code with the trace points.
This is a manual process.
While it is possible to intercept regular logs, snabbkaffe doesn't do that, and introduces a separate API instead.
This is a conscious decision:

1. Regular logs are formatted for humans, and they may be tricky to analyze by the machine.
1. Usually programmers do not expect test failures from merely changing the log messages.
   Using a distinct API helps indicating that the event is used somewhere.
1. Debug messages introduce some overhead, even when they are disabled by the logger configuration.
   Regular snabbkaffe traces completely disappear from the release build, so they can be placed in hot loops.
1. Snabbkaffe collector is designed to preserve ordering of the events,
   while logger can use buffering, filters or performance optimizations that are undesirable for the tests.
1. Snabbkaffe trace points are more than just logs, they can be used to modify the behavior of the SUT as well

The trace macros are defined in a header file that can be included like this:

```erlang
-include_lib("snabbkaffe/include/trace.hrl").
```

## ?tp

Snabbkaffe events are produced using `?tp` macro (tp stands for "trace point").
In its basic form it looks like this:

```erlang
?tp(my_event,
    #{ parameter1 => 1
     , parameter2 => foo
     , parameter3 => {1, 3}
     })
```

The first argument of the macro is called "kind".
It identifies the trace event.
Ideally, it should be unique through out the code base, since it will simplify analysis of the trace.
Kind can be an atom or a string.

The second parameter is a map that contains any additional data for the event.
The keys should be atoms, and the values are free-form.

The resulting event in will look like this in the trace:
```erlang
{ ?snk_kind => my_event
, ?snk_meta => #{ node => 'foo@localhost'
                , time => <monotonic time>
                , pid => <0.343.0>
                , group_leader => <0.67.0>
                }
, parameter1 => 1
, parameter2 => foo
, parameter3 => {1, 3}
}
```
If `logger:update_process_metadata/1` is used to add metadata to the process (e.g. `domain`), it will be added to `?snk_meta` field.
This macro disappears from the release build.

A trace point may be useful as a log message in the release build.
In this case, a different form of `?tp` can be used:

```erlang
?tp(notice, "Remote process died",
    #{ reason   => Reason
     , my_state => State
     })
```

The first argument of the macro is log level, as used by [logger](https://www.erlang.org/doc/man/logger.html#type-level).
The others are equivalent to the previous form of the macro.

## ?tp_ignore_side_effects_in_prod

This is made available as tool for optimizing specific use cases.  Usually, one shouldn't rely on side effects inside arguments of `?tp/2`.  If there's a need to introduce a trace point in a certain hot path for test efficiency purposes, but the arguments make expensive calls, then this macro is provided and won't ever evaluate its arguments in a production build.

## ?tp_span

Sometimes it is useful to emit two events before and after some action executes.
`?tp_span` is a shortcut that does that:

```erlang
?tp_span(foo, #{field1 => 42, field2 => foo},
         begin
           ...
         end).
```

It produces the following trace events:

```erlang
#{ ?snk_kind => foo
 , ?snk_meta => #{ ... }
 , ?snk_span => start
 , field1 => 42
 , field2 => foo
 },
...
#{ ?snk_kind => foo
 , ?snk_meta => #{ ... }
 , ?snk_span => {complete, ReturnValue}
 , field1 => 42
 , field2 => foo
 }
```

Log level for the span can be specified like in the previous example.

## Distributed tracing

Snabbkaffe supports distributed tracing.
`snabbkaffe:forward_trace(RemoteNode)` function will tell the remote node to forward traces to the local collector.

## ?snk_kind, ?snk_meta and ?snk_span macros

By default the values of `?snk_kind`, `?snk_meta` and `?snk_span` macros are set to `'$kind'`, `'~meta'` and `'$span'` respectively.
This is done so kind and span fields appear first in the printout, and meta field is printed last.
It makes traces and logs more readable.
But it is possible to redefine these macros, e.g.:

```erlang
{erl_opts, [{d, snk_kind, msg}]}.
```

Please keep in mind that it may collide with the regular fields, so it's better to avoid changing the defaults.

## ?SNK_COLLECTOR

By default the behavior of trace points is the following: in test build they emit traces, and in release build they either disappear or become regular logs.
In some tricky test setups it may be necessary to override the default behavior.
This can be done be defining `SNK_COLLECTOR` macro before including `trace.hrl`:

```erlang
%% Force snabbkaffe collector:
-define(SNK_COLLECTOR, true).
-include_lib("snabbkaffe/include/trace.hrl").
```

```erlang
%% Force regular logs:
-define(SNK_COLLECTOR, false).
-include_lib("snabbkaffe/include/trace.hrl").
```
