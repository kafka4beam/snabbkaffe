# Waiting for events during run stage

Snabbkaffe encourages to perform validation offline, in the check stage of the testcase.
However, some properties are impossible to verify offline.
Also the run stage may want to be aware of the SUT's state for one reason or another:
for example the testcase should know when the SUT is ready to accept test traffic, and when it is done processing it.

To accommodate these needs, snabbkaffe allows to subscribe to the events in real time.
There are a few helpful macros and functions for this.

## block_until

In the simplest case, `?block_until` macro can be used.
As the name suggests, it blocks execution of the testcase until an event matching a pattern is emitted:

```erlang
-module(waiting_events_example).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe/include/snabbkaffe.hrl").

async_action() ->
  timer:sleep(10),
  ?tp(complete, #{}).

basic_block_until_test() ->
  ?check_trace(
    %% Run stage:
    begin
      %% Start some async job:
      spawn(fun async_action/0),
      %% Wait for completion:
      ?block_until(#{?snk_kind := complete})
    end,
    %% Check stage:
    fun(Trace) ->
      %% Verify that the run stage always waits for the event:
      ?assertMatch([_], ?of_kind(complete, Trace))
    end).
```

The first argument of the macro is a match spec for the event.
It can be quite fancy, for example it can include guards:

```erlang
?block_until(#{?snk_kind := foo, bar := _Bar} when _Bar > 2)
```

If the matching event was found in the past, this macro will return immediately.
By default, it waits indefinitely.
In most situations it is the best behavior, since the timeout can be enforced by `timetrap` parameter discussed in the previous chapter.
But in some cases it may be necessary to set the timeout in place:

```erlang
block_until_timeout_test() ->
  ?check_trace(
    %% Run stage:
    begin
      %% Start some async job:
      spawn(fun async_action/0),
      %% Wait for completion:
      ?assertMatch({ok, _Event = #{}},
                   ?block_until(#{?snk_kind := complete}, _Timeout = 200))
    end,
    %% Check stage:
    fun(Trace) ->
      %% Verify that the run stage always waits for the event:
      ?assertMatch([_], ?of_kind(complete, Trace))
    end).
```

In this case it may be desirable to check the return value, which can be either `{ok, MatchingEvent}` or `timeout`.

Finally, the lookback behavior can be also customized:

```erlang
block_until_lookback_test() ->
  ?check_trace(
    %% Run stage:
    begin
      %% Start some async job:
      spawn(fun async_action/0),
      %% Wait for completion:
      ?block_until(#{?snk_kind := complete}, _Timeout = 200, _BackInTime = 200)
    end,
    %% Check stage:
    fun(Trace) ->
      %% Verify that the run stage always waits for the event:
      ?assertMatch([_], ?of_kind(complete, Trace))
    end).
```

In this case the macro will only look for the events that were produced no longer than 200 ms in the past.
However, this risks introducing flakiness into the testcase and should be avoided when possible.
If you find yourself tuning the lookback values, it's better to switch to more advanced macros described in the next section.

Finally, it's important to mention one caveat of this macro.
Consider the following code:

```erlang
trigger_async_action(foo),
?block_until(#{?snk_kind := action_complete}),
trigger_async_action(bar),
?block_until(#{?snk_kind := action_complete})
```

It will not work as you expect, since the second invocation of the macro will match the event emitted in the past and return immediately.
There are two solutions for this.

Firstly, it will help to refine the matching pattern, e.g.:

```erlang
trigger_async_action(foo),
?block_until(#{?snk_kind := action_complete, id := foo}),
trigger_async_action(bar),
?block_until(#{?snk_kind := action_complete, id := bar})
```

This way the second `?block_until` will ignore the unexpected events.

The second solution is to specify the number of events that need to happen before unblocking the testcase:

```erlang
block_until_multiple_events_test() ->
  ?check_trace(
    %% Run stage:
    begin
      %% Start async jobs:
      spawn(fun async_action/0),
      spawn(fun async_action/0),
      %% Wait for completion:
      snabbkaffe:block_until(?match_n_events(2, #{?snk_kind := complete}),
                             _Timeout    = infinity,
                             _BackInTIme = infinity)
    end,
    %% Check stage:
    fun(Trace) ->
      %% Verify that the run stage waited for both events:
      ?assertMatch([_, _], ?of_kind(complete, Trace))
    end).
```

## wait_async_action

In the previous section we discussed how starting multiple async actions and waiting for their completion using `?block_until` can lead to unexpected results.
To address this issue, snabbkaffe provides `?wait_async_action` macro:

```erlang
wait_async_action_test() ->
  ?check_trace(
    %% Run stage:
    begin
      ?wait_async_action(
         %% Trigger the action:
         begin
           spawn(fun async_action/0)
         end,
         %% Match pattern for the completion event:
         #{?snk_kind := complete}),
      %% Repeat:
      ?wait_async_action(
         %% Trigger the action:
         spawn(fun async_action/0),
         %% Match pattern:
         #{?snk_kind := complete},
         %% Optional timeout:
         100)
    end,
    %% Check stage:
    fun(Trace) ->
      %% Verify completion of both actions:
      ?assertMatch([_, _], ?of_kind(complete, Trace))
    end).
```

`?wait_async_action` installs a watcher before running the code from the first argument, so it doesn't have to look in the past.
It returns a tuple `{ActionResult, {ok, Event}}` or `{ActionResult, timeout}`.

## subscribe/receive_events

When the testcase gets really complicated, and it has to wait for multiple events of different kinds, the simple macros may not be enough.
In this section we will introduce the most flexible of the real time trace inspection APIs.
A pair of `snabbkaffe_collector:subscribe/3` and `snabbkaffe_collector:receive_events/1` functions can be used in the tricky situations.
The first one installs a watcher that will wait for a specified number of events matching a pattern.
The second function takes an opaque reference returned by the first call, and blocks execution until the events are produced, or until timeout.

```erlang
subscribe_receive_test() ->
  ?check_trace(
     begin
       {ok, SubRef} = snabbkaffe_collector:subscribe(?match_event(#{?snk_kind := complete}),
                                                     _NEvents    = 2,
                                                     _Timeout    = infinity,
                                                     _BackInTime = 0),
       spawn(fun async_action/0),
       spawn(fun async_action/0),
       ?assertMatch({ok, [#{?snk_kind := complete},
                          #{?snk_kind := complete}
                         ]},
                    snabbkaffe_collector:receive_events(SubRef))
     end,
     []).
```

The return type of `receive_events` is `{ok | timeout, ListOfMatchedEvents}`.
If the number of received events is equal to the number of events specified in the `subscribe` call, the first element of the tuple is `ok`, and `timeout` otherwise.
Pairs of `subscribe`/`receive_events` calls can be nested.

Side note: both `?block_until` and `?wait_async_action` use this API internally.

## retry

Snabbkaffe aims to eliminate "retry function N times until it succeeds" anti-pattern in tests.
However, in some situations it's inevitable.
So it provides a macro to avoid ad-hoc implementations:

```erlang
retry_test() ->
  ?retry(_Interval = 100, _NRepeats = 10,
         begin
           %% Some code
           ok
         end).
```

It will retry the body of the macro N times with a specified interval, until it succeeds (i.e. returns a value instead of throwing an exception).
