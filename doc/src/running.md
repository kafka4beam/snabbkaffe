# Running the testcases

This chapter describes the high-level structure of the snabbkaffe testcase.
Most of the work is done by `?check_trace` macro, which can be placed inside eunit, Common Test or proper testcase.

## check_trace
In the most basic form, Snabbkaffe tests look like this:

```erlang
-module(running_example).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe/include/snabbkaffe.hrl").

basic_test() ->
  ?check_trace(
     %% Run stage:
     begin
       ?tp(some_event, #{foo => foo, bar => bar})
     end,
     %% Check stage:
     fun(RunStageResult, Trace) ->
         ?assertMatch(ok, RunStageResult),
         ?assertMatch([#{foo := _}], ?of_kind(some_event, Trace))
     end).
```

`?check_trace` macro performs the following steps:

1. Start the snabbkaffe supervision tree
1. Produce `#{?snk_kind := '$trace_begin'}` event
1. Execute the code specified in the run stage section
1. Wait for the silence interval (if `timeout` option is set, see below)
1. Produce `#{?snk_kind := '$trace_end'}` event
1. Collect the trace
1. Execute the offline checks on the collected trace

If either run stage or check stage fails, `?check_trace` dumps the collected trace to a file and throws an exception that is detected by eunit or Common Test.
The trace dumps are placed to `snabbkaffe` sub-directory of the current working directory.

If the return value from the run stage is not needed in the check stage, it can be omitted:

```erlang
ignore_return_test() ->
  ?check_trace(
     %% Run stage:
     begin
       ok
     end,
     %% Check stage:
     fun(_Trace) ->
       ok
     end).
```

If the testcase allocates any resources that should be released after the completion of the run stage, it is recommended to use the following construct:

```erlang
try_after_test() ->
  ?check_trace(
    try
      %% Allocate resources...
      ets:new(foo, [named_table]),
      %% Run test
      ok
    after
      ets:delete(foo)
    end,
    %% Check stage:
    [fun ?MODULE:common_trace_spec/1,
     fun ?MODULE:common_trace_spec/2,
     {"Another trace spec",
      fun(_Result, _Trace) ->
        true
      end}
    ]).

%% Make sure the trace is a list:
common_trace_spec(Trace) ->
  ?assert(is_list(Trace)).

%% Check the return value of the run stage:
common_trace_spec(Result, _Trace) ->
  ?assertMatch(ok, Result).
```

Notice another new thing in the above example: the check stage is defined as a list of callbacks.
This form allows to reuse trace specifications in multiple tests.

## check_trace options

`?check_trace` macro can accept some additional arguments:

```erlang
options_test_() ->
  {timeout, 15,
    [fun() ->
       ?check_trace(
         #{timetrap => 10000, timeout => 1000},
         %% Run stage:
         ok,
         %% Check stage:
         [])
     end]}.
```

`timetrap` specifies how long the run stage can execute (in milliseconds).
If this time is exceeded, the testcase fails and the trace is dumped.
It is recommended to handle the timeouts using `timetrap` in `?check_trace`, rather than at Common Test or eunit level, because it will produce a better error message and a trace dump.

`timeout` parameter specifies "silence interval" for the testcase.
If it is set to `T`, upon completion of the run stage snabbkaffe will wait for events arriving within `T` milliseconds after the last received event.

By default snabbkaffe removes parts of the stacktrace that are internal for the test frameworks (such as `ct`, `eunit` and `proper`).
This behavior can be disabled using `tidy_stacktrace => false` option.

## Integrating with PropEr

There are two useful macros for running snabbkaffe together with [PropER](https://proper-testing.github.io/):

```erlang
proper_test() ->
  Config = #{proper => #{ numtests => 100
                        , timeout  => 5000
                        , max_size => 100
                        },
             timetrap => 1000},
  ?run_prop(Config, prop()).

prop() ->
  ?FORALL({_Ret, _L}, {term(), list()},
         ?check_trace(
            %% Run stage:
            ok,
            %% Check stage:
            [ fun ?MODULE:common_trace_spec/1
            ])).
```

`proper` key of the `Config` contains the parameters accepted by PropEr.
Snabbkaffe will fall back to the default values (shown above) when parameter is absent.

`?FORALL(Var, Generator, ?check_trace(...))` construct is used very often, so snabbkaffe provides a shortcut:

```erlang
simple_prop_test() ->
  ?run_prop(#{}, simple_prop()).

simple_prop() ->
  ?forall_trace({_Ret, _L}, {term(), list()},
                %% Run stage:
                ok,
                %% Check stage:
                [ fun ?MODULE:common_trace_spec/1
                ]).
```

It is equivalent to the previous example.
