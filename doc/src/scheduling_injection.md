# Injecting schedulings into the SUT

Finally, snabbkaffe can not only check the ordering of events, but also affect it.
This is useful for testing code for potential race conditions and exploring rare scenarios.
For example, there may be two processes `A` and `B` that are needed for processing data.
Usually process `A` initialises earlier than `B`, but scheduling injection allows to reliably test what happens when `B` initialises earlier.

It is also useful for testing state machines _in situ_: it can delay state transition and force the FSM to accept events in the specified state.

## ?force_ordering

```erlang
?force_ordering(ContinuePattern [, N], DelayedPattern [, Guard])
```

Parameters:
- `ContinuePattern`: match pattern for the event that should happen first.
- `N` (optional): number of event matching `ContinuePattern` that should happen first.
  Defaults to 1.
- `DelayedPattern`: match pattern for the events that will be delayed until N `ContinuePattern` events are emitted.
- `Guard` (optional): guard function similar to that in `?strict_causality` pattern.

Example:
```erlang
-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe/include/snabbkaffe.hrl").

force_ordering_test() ->
  ?check_trace(
    %% Check trace:
    begin
      %% Inject schedulings:
      ?force_ordering(#{id := 1}, #{id := 2}),
      ?force_ordering(#{id := 2}, #{id := 3}),
      %% Start a few concurrent processes:
      spawn(fun() -> ?tp(foo, #{id => 1}) end),
      spawn(fun() -> ?tp(foo, #{id => 2}) end),
      spawn(fun() -> ?tp(foo, #{id => 3}) end),
      %% Wait completion:
      [?block_until(#{id := I}) || I <- lists:seq(1, 3)]
    end,
    fun(Trace) ->
      %% Under the normal conditions the three processes can
      %% execute in any order, but since we injected the
      %% scheduling, they will always run in this order:
      ?assertMatch([1, 2, 3],
                   ?projection(id, ?of_kind(foo, Trace)))
    end).
```

Warning: this macro will create a deadlock if the forced ordering reverses logical causality of the events.
