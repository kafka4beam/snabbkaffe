%% Copyright 2019-2020, 2022 Klarna Bank AB
%% Copyright 2021 snabbkaffe contributors
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% @private This module controls the event collection
-module(snabbkaffe_collector).

-include("snabbkaffe_internal.hrl").

-behaviour(gen_server).

%% API
-export([ start_link/0
        , flush_trace/0
        , get_stats/0
        , block_until/3
        , subscribe/4
        , receive_events/1
        , tp/3
        , push_stat/3
        ]).

%% Internal exports
-export([ wait_for_silence/1
        , make_begin_trace/0
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Internal exports:
-export([ do_forward_trace/1
        ]).

-export_type([async_action/0, subscription/0]).

-define(SERVER, ?MODULE).

-type datapoints() :: [{number(), number()}]
                    | number().

-type async_action() :: fun(({ok, snabbkaffe:event()} | timeout) -> _).

-record(callback,
        { process   :: pid()
        , predicate :: snabbkaffe:predicate()
        , ref       :: reference()
        , n         :: non_neg_integer()
        }).

-record(subscription,
        { ref  :: reference()
        , tref :: reference() | undefined
        , n    :: non_neg_integer()
        }).

-opaque subscription() :: #subscription{}.

-record(s,
        { trace             :: [snabbkaffe:timed_event()]
        , stats = #{}       :: #{snabbkaffe:metric() => datapoints()}
        , last_event_ts = 0 :: integer()
        , callbacks = []    :: [#callback{}]
        }).

%%%===================================================================
%%% API
%%%===================================================================

-spec tp(logger:level(), map(), logger:metadata()) -> ok.
tp(Level, Event, Metadata0) ->
  Metadata = Metadata0 #{time => timestamp()},
  logger:log(Level, Event, Metadata0),
  EventAndMeta = Event #{?snk_meta => Metadata},
  %% Call or cast? This is a tricky question, since we need to
  %% preserve causality of trace events. Per documentation, Erlang
  %% doesn't guarantee order of messages from different processes. So
  %% call looks like a safer option. However, when testing under
  %% concuerror, calls to snabbkaffe generate a lot (really!) of
  %% undesirable interleavings. In the current BEAM implementation,
  %% however, sender process gets blocked while the message is being
  %% copied to the local receiver's mailbox. That leads to
  %% preservation of causality. Concuerror uses this fact, as it runs
  %% with `--instant_delivery true` by default.
  %%
  %% Above reasoning is only valid for local processes.
  gen_server:cast(?SERVER, {trace, EventAndMeta}).

-spec push_stat(snabbkaffe:metric(), number() | undefined, number()) -> ok.
push_stat(Metric, X, Y) ->
  Val = case X of
          undefined ->
            Y;
          _ ->
            {X, Y}
        end,
  gen_server:call(?SERVER, {push_stat, Metric, Val}, infinity).

start_link() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

-spec get_stats() -> #{snabbkaffe:metric() => datapoints()}.
get_stats() ->
  gen_server:call(?SERVER, get_stats, infinity).

%% NOTE: Concuerror only supports `Timeout=0'
-spec flush_trace() -> snabbkaffe:timed_trace().
flush_trace() ->
  {ok, Trace} = gen_server:call(?SERVER, flush_trace, infinity),
  Trace.

%% NOTE: concuerror supports only `Timeout = infinity' and `BackInType = infinity'
%% or `BackInTime = 0'
-spec block_until(snabbkaffe:filter(), timeout(), timeout()) ->
        {ok, snabbkaffe:event()} | timeout |
        {ok, [snabbkaffe:event()]} | {timeout, [snabbkaffe:event()]}.
block_until(Predicate, Timeout, BackInTime) when is_function(Predicate) ->
  {ok, Sub} = subscribe(Predicate, 1, Timeout, BackInTime),
  case receive_events(Sub) of
    {ok, [Evt]} ->
      {ok, Evt};
    {timeout, []} ->
      timeout
  end;
block_until({Predicate, NEvents}, Timeout, BackInTime) ->
  {ok, Sub} = subscribe(Predicate, NEvents, Timeout, BackInTime),
  receive_events(Sub).

-spec subscribe(snabbkaffe:predicate(), non_neg_integer(), timeout(), timeout()) ->
        {ok, subscription()}.
subscribe(Predicate, NEvents, Timeout, BackInTime) when NEvents > 0 ->
  Infimum = infimum(BackInTime),
  SubRef = monitor(process, whereis(?SERVER)),
  ok = gen_server:call( ?SERVER
                      , {subscribe, Predicate, NEvents, Infimum, SubRef, self()}
                      , infinity
                      ),
  TRef = send_after(Timeout, self(), {SubRef, timeout}),
  {ok, #subscription{ ref  = SubRef
                    , tref = TRef
                    , n    = NEvents
                    }}.

-spec receive_events(subscription()) -> {ok | timeout, [snabbkaffe:event()]}.
receive_events(Sub = #subscription{ref = Ref, n = NEvents}) ->
  Ret = do_recv_events(Ref, NEvents, []),
  unsubscribe(Sub),
  Ret.

%% @doc NOTE: This function should be called from the same process
%% that subscribed to `SubRef'
-spec unsubscribe(subscription()) -> ok.
unsubscribe(#subscription{ref = SubRef, tref = TRef}) ->
  ok = gen_server:call( ?SERVER
                      , {unsubscribe, SubRef}
                      , infinity
                      ),
  demonitor(SubRef, [flush]),
  cancel_timer(TRef),
  flush_events(SubRef).

-spec wait_for_silence(integer()) -> ok.
wait_for_silence(0) ->
  ok;
wait_for_silence(SilenceInterval) when SilenceInterval > 0 ->
  do_wait_for_silence(SilenceInterval, SilenceInterval).


%%%===================================================================
%%% Internal exports
%%%===================================================================

-spec get_last_event_ts() -> integer().
get_last_event_ts() ->
  gen_server:call(?SERVER, get_last_event_ts, infinity).


make_begin_trace() ->
    #{ ts                => timestamp()
     , begin_system_time => os:system_time(microsecond)
     , ?snk_kind         => '$trace_begin'
     }.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  persistent_term:put(?PT_TP_FUN, fun snabbkaffe:local_tp/5),
  #{ts := TS} = BeginTrace = make_begin_trace(),
  {ok, #s{ trace         = [BeginTrace]
         , last_event_ts = TS
         }}.

handle_cast({trace, Evt}, State0 = #s{trace = T0, callbacks = CB0}) ->
  CB = maybe_notify_someone(Evt, CB0),
  State = State0#s{ trace         = [Evt|T0]
                  , last_event_ts = timestamp()
                  , callbacks     = CB
                  },
  {noreply, State};
handle_cast(_Evt, State) ->
  {noreply, State}.

handle_call({trace, Evt}, _From, State0 = #s{trace = T0, callbacks = CB0}) ->
  CB = maybe_notify_someone(Evt, CB0),
  State = State0#s{ trace         = [Evt|T0]
                  , last_event_ts = timestamp()
                  , callbacks     = CB
                  },
  {reply, ok, State};
handle_call({push_stat, Metric, Stat}, _From, State0) ->
  Stats = maps:update_with( Metric
                          , fun(L) -> [Stat|L] end
                          , [Stat]
                          , State0#s.stats
                          ),
  {reply, ok, State0#s{stats = Stats}};
handle_call(get_stats, _From, State) ->
  {reply, {ok, State#s.stats}, State};
handle_call(flush_trace, _From, State) ->
  do_flush_trace(State);
handle_call({subscribe, Predicate, NEvents, Infimum, SubRef, Process}, _From, State0) ->
  State = handle_subscribe(Predicate, NEvents, Infimum, SubRef, Process, State0),
  {reply, ok, State};
handle_call({unsubscribe, Ref}, _From, State = #s{callbacks = Callbacks0}) ->
  Callbacks = lists:keydelete(Ref, #callback.ref, Callbacks0),
  {reply, ok, State#s{callbacks = Callbacks}};
handle_call(get_last_event_ts, _From, State = #s{last_event_ts = LastEventTs}) ->
  {reply, LastEventTs, State};
handle_call(_Request, _From, State) ->
  Reply = unknown_call,
  {reply, Reply, State}.

handle_info(_, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  persistent_term:erase(?PT_TP_FUN),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_flush_trace(#s{trace = Trace, last_event_ts = LastEventTs} = State) ->
  TraceEnd = #{ ?snk_kind => '$trace_end'
              , ?snk_meta => #{time => LastEventTs}
              },
  Result = {ok, lists:reverse([TraceEnd|Trace])},
  {reply, Result, State #s{trace = []}}.

-spec maybe_notify_someone( snabbkaffe:event()
                          , [#callback{}]
                          ) -> [#callback{}].
maybe_notify_someone(Evt, Callbacks) ->
  Fun = fun(Callback0 = #callback{predicate = Predicate}) ->
            case Predicate(Evt) of
              true ->
                Callback = send_event(Evt, Callback0),
                if Callback#callback.n > 0 ->
                    {true, Callback};
                   true ->
                    false
                end;
              false ->
                {true, Callback0}
            end
        end,
  lists:filtermap(Fun, Callbacks).

-spec handle_subscribe( snabbkaffe:predicate()
                      , non_neg_integer()
                      , integer()
                      , reference()
                      , pid()
                      , #s{}
                      ) -> #s{}.
handle_subscribe(Predicate, NEvents, Infimum, SubRef, Process, State0) ->
  #s{ trace     = Trace
    , callbacks = CB0
    } = State0,
  Callback0 = #callback{ process   = Process
                       , predicate = Predicate
                       , ref       = SubRef
                       , n         = NEvents
                       },
  %% 1. Search in the past events:
  Events = look_back(NEvents, Predicate, Infimum, Trace, []),
  %% 2. Send back the past events:
  Callback = lists:foldl(fun send_event/2, Callback0, Events),
  %% 3. Have we sent all of them? If not add the subscriber
  NLeft = Callback#callback.n,
  if NLeft > 0 ->
      State0#s{callbacks = [Callback|CB0]};
     NLeft =:= 0 ->
      State0
  end.

-spec send_event(snabbkaffe:event(), #callback{}) -> #callback{}.
send_event(Event, CB = #callback{process = Pid, ref = Ref, n = NLeft}) ->
  Pid ! {Ref, Event},
  CB#callback{n = NLeft - 1}.

-spec send_after(timeout(), pid(), _Msg) ->
                    reference() | undefined.
send_after(infinity, _, _) ->
  undefined;
send_after(Timeout, Pid, Msg) ->
  erlang:send_after(Timeout, Pid, Msg).

-spec infimum(timeout()) -> integer().
-ifndef(CONCUERROR).
infimum(infinity) ->
  beginning_of_times();
infimum(BackInTime0) ->
  BackInTime = erlang:convert_time_unit( BackInTime0
                                       , millisecond
                                       , microsecond
                                       ),
  timestamp() - BackInTime.
-else.
infimum(infinity) ->
  beginning_of_times();
infimum(_) ->
  %% With concuerror, all events have `timestamp=-1', so
  %% starting from 0 should not match any events:
  0.
-endif.

-spec timestamp() -> integer().
-ifndef(CONCUERROR).
timestamp() ->
  erlang:monotonic_time(microsecond).
-else.
timestamp() ->
  -1.
-endif.

-spec beginning_of_times() -> integer().
-ifndef(CONCUERROR).
beginning_of_times() ->
  erlang:convert_time_unit( erlang:system_info(start_time)
                          , native
                          , microsecond
                          ).
-else.
beginning_of_times() ->
  -2.
-endif.

%% @private Internal export
-spec do_forward_trace(node()) -> ok.
do_forward_trace(Node) ->
  ok = persistent_term:put(?PT_REMOTE, Node),
  ok = persistent_term:put(?PT_TP_FUN, fun snabbkaffe:remote_tp/5),
  ?tp(notice, '$snabbkaffe_remote_attach',
      #{ parent => Node
       , node   => node()
       }).

-spec look_back(non_neg_integer(),
                snabbkaffe:predicate(),
                integer(),
                [snabbkaffe:event()],
                [snabbkaffe:event()]
               ) -> [snabbkaffe:event()].
look_back(0, _Predicate, _Infimum, _Trace, Acc) ->
  %% Got enough events:
  Acc;
look_back(_N, _Predicate, _Infimum, [], Acc) ->
  %% Reached the end of the trace:
  Acc;
look_back(_N, _Predicate, Infimum, [#{?snk_meta := #{time := TS}}|_], Acc) when TS =< Infimum ->
  %% Reached the end of specified time interval:
  Acc;
look_back(N, Predicate, Infimum, [Evt|Trace], Acc) ->
  case Predicate(Evt) of
    true  -> look_back(N - 1, Predicate, Infimum, Trace, [Evt|Acc]);
    false -> look_back(N, Predicate, Infimum, Trace, Acc)
  end.

%% TODO: Remove
-spec cancel_timer(reference() | undefined) -> _.
cancel_timer(undefined) ->
  ok;
cancel_timer(TRef) ->
  erlang:cancel_timer(TRef).

flush_events(SubRef) ->
  receive
    {SubRef, _} -> flush_events(SubRef)
  after
    0 -> ok
  end.

-spec do_recv_events(reference(),
                     non_neg_integer(),
                     [snabbkaffe:event()]
                    ) -> {ok | timeout, [snabbkaffe:event()]}.
do_recv_events(_Ref, 0, Acc) ->
  {ok, lists:reverse(Acc)};
do_recv_events(Ref, N, Acc) ->
  receive
    {'DOWN', Ref, _, _, _} ->
      exit(snabbkaffe_collector_died);
    {Ref, timeout} ->
      {timeout, lists:reverse(Acc)};
    {Ref, Event} ->
      do_recv_events(Ref, N - 1, [Event|Acc])
  end.

-spec do_wait_for_silence(integer(), integer()) -> ok.
do_wait_for_silence(SilenceInterval, SleepTime) ->
  timer:sleep(SleepTime),
  Dt = erlang:convert_time_unit( timestamp() - get_last_event_ts()
                               , microsecond
                               , millisecond
                               ),
  if Dt >= SilenceInterval ->
      ok;
     true ->
      do_wait_for_silence(SilenceInterval, SilenceInterval - Dt)
  end.
