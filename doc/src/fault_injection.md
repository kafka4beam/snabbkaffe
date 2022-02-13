# Injecting faults into the SUT

Snabbkaffe allows to inject crashes into any trace point.
This is useful for tuning supervision trees and testing fault tolerance of the system.
Snabbkaffe comes with a number of "fault scenarios" that emulate recoverable or transient failures.

## ?inject_crash

`?inject_crash` macro is used for injecting faults into the system.
The first argument of this macro is a match pattern for events, and the second argument is fault scenario.
The return value is an opaque reference that can be used to remove the injected fault.
Note: injected crashes are global, they work on the remote nodes.

Example:

```erlang
-module(fault_injection_example).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("eunit/include/eunit.hrl").

inject_failure_test() ->
  ?check_trace(
    %% Run stage
    begin
      %% Inject crashes:
      ?inject_crash(#{?snk_meta := #{domain := [my,domain|_]}},
                    snabbkaffe_nemesis:always_crash()),
      %% Start the system:
      logger:update_process_metadata(#{domain => [my, domain]}),
      %% Any trace point matching the injected crash pattern will fail now:
      ?assertExit(_, ?tp(some_event, #{}))
    end,
    fun(Trace) ->
      %% Injected failures are recorded in the trace:
      ?assertMatch([_],
                   ?of_kind(snabbkaffe_crash, Trace))
    end).
```

## fix_crash

`snabbkaffe_nemesis:fix_crash(Ref)` removes an injected crash.
It takes one argument: the reference returned by `?inject_crash` macro.

# Fault scenarios

## always_crash

As the name suggests, this fault scenario always generates crashes.

Example:
```erlang
?inject_crash(..., snabbkaffe_nemesis:always_crash())
```

## recover_after

This fault scenario imitates a recoverable crash.
It will generate `N` crashes, then the code will execute normally.

```erlang
?inject_crash(..., snabbkaffe_nemesis:recover_after(10))
```

## random_crash

This fault scenario generates random crashes with probability `P`.

Example:
```erlang
?inject_crash(..., snabbkaffe_nemesis:random_crash(0.1))
```

## periodic_crash

This fault scenario generates crashes periodically.
It takes three parameters:

- period: number of matching events until the cycle repeats
- duty cycle: ratio of successes to failures
- phase: 0..2π, acts similar to phase of a sine function

Example:
```erlang
snabbkaffe_nemesis:periodic_crash(
  _Period = 10, _DutyCycle = 0.5, _Phase = math:pi())
```

To illustrate how the parameters affect the behavior, consider the examples:
- `snabbkaffe_nemesis:periodic_crash(4, 0.5, 0)`: `[ok,ok,crash,crash,ok,ok,crash,crash,ok,ok,crash,...]`
- `snabbkaffe_nemesis:periodic_crash(4, 0.5, math:pi())`: `[crash,crash,ok,ok,crash,crash,ok,ok,crash,crash,...]`
- `snabbkaffe_nemesis:periodic_crash(4, 0.25, 0)`: `[ok,crash,crash,crash,ok,crash,crash,crash,ok,crash,crash,...]`
