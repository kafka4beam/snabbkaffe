# Changelog

## 1.0.3
### Features
- Clean stack traces from entries related to the test framework internals (can be disabled with `tidy_stacktrace => false` config)

## 1.0.2
### Fixes
- Fix unused variables compilation warnings for `?tp(kind, _)` macro in prod mode

## 1.0.0
### Features
- Publish documentation
### Fixes
- `snabbkaffe_collector:subscribe` and `receive_events` have been moved to `snabbkaffe` module
- Fix off-by-one error in `snabbkaffe_nemesis:periodic_crash/3`

## 0.18.0
### Features
- Introduce `snabbkaffe:increasing` and `snabbkaffe:check_conseq_relation` functions

## 0.17.0
### Features
- Introduce `snabbkaffe:dump_trace/1` function that saves trace to a file
- Allow to change behavior of trace points by defining `SNK_COLLECTOR` macro as `true` or `false` (the latter means log trace points instead of collecting them)

### Fixes
- Fix compilation warnings
- Improve output of `snabbkaffe:strictly_increasing` function

### Non-BC changes
- API of `find_pairs` function and macro are heavily reworked: `Strict` flag has been removed and the return type has been changed.
  Now they don't crash when they find an effect without a cause, but instead add it to the list.

## 0.16.0
### Features
- Passing return value to the check stage callback is made optional:

```erlang
?check_trace(
   RunStage,
   fun(Trace) ->
       ...
   end)
```

- Check stage supports a list of callbacks in the following form:

```erlang
?check_trace(
   RunStage,
   [ fun trace_check/1
   , fun another_trace_check/2
   , {"There are no crashes", fun(Trace) -> ... end}
   , {"Another important check", fun(Return, Trace) -> ... end}
   ])
```

### Fixes
- Fix timetrap while waiting for the silence interval

### Non-BC changes
- The check stage now must return ok or true to indicate success

## 0.15.0
### Fixes
- Fix race condition in the injected fault

### Features
- Improved event subscription mechanism using new APIs: `snabbkaffe_collector:subcribe` and `receive_events`, that aim to replace the `?wait_async_action` macro:

```erlang
{ok, Sub} = snabbkaffe_collector:subscribe( ?match_event(#{?snk_kind := foo})
                                          , _Quantity = 2
                                          , _Timeout = infinity
                                          , _BackInTime = 0
                                          ),
... trigger async action ...
?assertMatch( {ok, [ #{?snk_kind := foo, n := 1}
                   , #{?snk_kind := foo, n := 2}
                   ]}
            , snabbkaffe_collector:receive_events(Sub)),
```

- `?block_until` macro support waiting for multiple events

- `snabbkaffe:fix_ct_logging` function includes node name in the logs

### Non-BC fixes
- Error injection uses `erlang:exit` instead of `erlang:error`. This
  may affect a small portion of testcases that specifically expect
  certain errors

## 0.14.1
### Fixes
- Fix `?of_kind` and `?of_domain` macros

## 0.14.0
### Features
- Timetrap: fail a testcase and dump the trace if the run stage takes too long to complete

## 0.13.0
### Features
- Allow user to redefine the values of `?snk_kind`, `?snk_span` and `?snk_meta` macros

## 0.12.0
### Features
- Allow to specify severity for `?tp_span` macro

### Fixes
- Move MFA tuple to the log metadata in the prod mode

## 0.11.0
### Non-BC fixes
- `?split_trace_at`, `?splitl_trace` and `?splitr_trace` macros now use inverse matching.
  It was the original intention, but the fix is non-BWC

## 0.10.1
### Features
- `snabbkaffe.hrl` has been split into parts related to tracing and
  running the tests
## 0.10.0
### Breaking changes
- `snabbkaffe:strictly_increasing` function returns false when the
  list is empty

### Features
- Add `?tp_span` macro that wraps around a piece of code and emits
  trance events when entering and completing it

### Fixes
- Fix type specs

## 0.9.1
### Features
- Any term can be used as metric name
- snabbkaffe:push_stat work on remote nodes

### Fixes
- Don't filter out metrics that have less than 5 samples

## 0.9.0
### Breaking changes
- Tracepoints without severity no longer appear in the release build
  as debug logs. Old behavior can be emulated by explicitly specifying
  debug severity using `?tp(debug, Kind, Data)` macro
- Timestamp field (`tp`) has been moved to the metadata and renamed to
  `time`. Its resolution has been changed to microsecond.

### Features
- Add `logger` process metadata to the trace events
- Add `?of_domain` and `?of_node` macros
- Severity level of tracepoints affects severity of logs in the debug mode

## 0.8.2

### Fixes
- Fix execution of tracepoints in TEST profile while snabbkaffe collector is not running

## 0.8.1
### Breaking changes
- Change return type of `?causality` and `?strict_causality` macros to boolean

### Features
- Introduce `?force_ordering` macro
- Introduce support for distributed tracing. `snabbkaffe:forward_trace/1` function.

### Fixes
- Remove dependency on `bear`

## 0.7.0
### Breaking changes
- Drop support for OTP releases below 21
- Drop `hut` dependency, now in the release profile snabbkaffe always uses `kernel` logger

### Features
- Kind of the trace point now can be a string
- Concuerror support

### Fixes
- `?projection_complete` and `?projection_is_subset` macros now support multiple fields
- Allow usage of guards in the match patterns in all macros
