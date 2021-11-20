%% Copyright 2019-2020 Klarna Bank AB
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
-module(snabbkaffe).

-include("snabbkaffe_internal.hrl").

%% API exports
-export([ tp/4
        , start_trace/0
        , forward_trace/1
        , stop/0
        , cleanup/0
        , collect_trace/0
        , collect_trace/1
        , block_until/2
        , block_until/3
        , wait_async_action/3
        , push_stat/2
        , push_stat/3
        , push_stats/2
        , push_stats/3
        , analyze_statistics/0
        , get_stats/0
        , run/3
        , get_cfg/3
        , fix_ct_logging/0
        , splitl/2
        , splitr/2
        , proper_printout/2
        ]).

-export([ events_of_kind/2
        , projection/2
        , erase_timestamps/1
        , find_pairs/5
        , causality/5
        , unique/1
        , projection_complete/3
        , projection_is_subset/3
        , pair_max_depth/1
        , inc_counters/2
        , dec_counters/2
        , strictly_increasing/1
        ]).

-export([ mk_all/1
        , retry/3
        ]).

%% Internal exports:
-export([ local_tp/5
        , remote_tp/5
        ]).

%%====================================================================
%% Types
%%====================================================================

-type kind() :: atom() | string().

-type metric() :: atom().

-type timestamp() :: integer().

-type event() ::
        #{ ?snk_kind := kind()
         , ?snk_meta := map()
         , _ => _
         }.

-type timed_event() ::
        #{ ?snk_kind := kind()
         , ts   := timestamp()
         , _ => _
         }.

-type trace() :: [event()].

-type maybe_pair() :: {pair, timed_event(), timed_event()}
                    | {singleton, timed_event()}.

-type maybe(A) :: {just, A} | nothing.

-type run_config() ::
        #{ bucket   => integer()
         , timeout  => integer()
         , timetrap => integer()
         }.

-type predicate() :: fun((event()) -> boolean()).

-type predicate2() :: fun((event(), event()) -> boolean()).

-type filter() :: predicate() | {predicate(), non_neg_integer()}.

-export_type([ kind/0, timestamp/0, event/0, timed_event/0, trace/0
             , maybe_pair/0, maybe/1, metric/0, run_config/0, predicate/0
             , predicate2/0
             ]).

%%====================================================================
%% Macros
%%====================================================================

%%====================================================================
%% API functions
%%====================================================================

-spec tp(term(), logger:level(), kind(), map()) -> ok.
-ifndef(CONCUERROR).
tp(Location, Level, Kind, Data) ->
  Fun = persistent_term:get(?PT_TP_FUN, fun local_tp/5),
  apply(Fun, [Location, Level, Kind, Data, get_metadata()]).
-else.
tp(Location, Level, Kind, Data) ->
  local_tp(Location, Level, Kind, Data, get_metadata()).
-endif. %% CONCUERROR

-spec local_tp(term(), logger:level(), kind(), map(), map()) -> ok.
local_tp(Location, Level, Kind, Data, Metadata) ->
  Event = Data #{?snk_kind => Kind},
  EventAndMeta = Event #{ ?snk_meta => Metadata },
  snabbkaffe_nemesis:maybe_delay(EventAndMeta),
  snabbkaffe_nemesis:maybe_crash(Location, EventAndMeta),
  snabbkaffe_collector:tp(Level, Event, Metadata).

-spec remote_tp(term(), logger:level(), kind(), map(), map()) -> ok.
remote_tp(Location, Level, Kind, Data, Meta) ->
  Node = persistent_term:get(?PT_REMOTE),
  %% TODO: replacing local_tp with tp will allow to diasy chain nodes, not sure if needed
  case rpc:call(Node, snabbkaffe, local_tp, [Location, Level, Kind, Data, Meta], infinity) of
    ok -> ok;
    {badrpc, {'EXIT', Reason}} -> exit(Reason)
  end.

-spec collect_trace() -> trace().
collect_trace() ->
  collect_trace(0).

-spec collect_trace(integer()) -> trace().
collect_trace(Timeout) ->
  snabbkaffe_collector:wait_for_silence(Timeout),
  snabbkaffe_collector:flush_trace().

%% @equiv block_until(Filter, Timeout, 100)
-spec block_until(filter(), timeout()) -> {ok, event()} | timeout.
block_until(Filter, Timeout) ->
  block_until(Filter, Timeout, 100).

-spec wait_async_action(fun(() -> Return), predicate(), timeout()) ->
                           {Return, {ok, event()} | timeout}.
wait_async_action(Action, Predicate, Timeout) ->
  {ok, Sub} = snabbkaffe_collector:subscribe(Predicate, 1, Timeout, 0),
  Return = Action(),
  case snabbkaffe_collector:receive_events(Sub) of
    {timeout, []} ->
      {Return, timeout};
    {ok, [Event]} ->
      {Return, {ok, Event}}
  end.

%% @doc Block execution of the run stage of a testcase until an event
%% matching `Predicate' is received or until `Timeout'.
%%
%% <b>Note</b>: since the most common use case for this function is
%% the following:
%%
%% ```trigger_produce_event_async(),
%%    snabbkaffe:block_until(MatchEvent, 1000)
%% ```
%%
%% there is a possible situation when the event is emitted before
%% `block_until' function has a chance to run. In this case the latter
%% will time out for no good reason. In order to work around this,
%% `block_until' function actually searches for events matching
%% `Predicate' in the past. `BackInTime' parameter determines how far
%% back into past this function peeks.
%%
%% <b>Note</b>: In the current implementation `Predicate' runs for
%% every received event. It means this function should be lightweight
-spec block_until(filter(), timeout(), timeout()) ->
                     event() | timeout.
block_until(Filter, Timeout, BackInTime) ->
  snabbkaffe_collector:block_until(Filter, Timeout, BackInTime).

-spec start_trace() -> ok.
start_trace() ->
  case snabbkaffe_sup:start_link() of
    {ok, _} ->
      ok;
    {error, {already_started, _}} ->
      ok
  end.

-spec stop() -> ok.
stop() ->
  snabbkaffe_sup:stop(),
  ok.

-spec cleanup() -> ok.
cleanup() ->
  _ = collect_trace(0),
  snabbkaffe_nemesis:cleanup().

%% @doc Forward traces from the remote node to the local node.
-spec forward_trace(node()) -> ok.
forward_trace(Node) ->
  Self = node(),
  ok = rpc:call(Node, snabbkaffe_collector, do_forward_trace, [Self]).

%% @doc Extract events of certain kind(s) from the trace
-spec events_of_kind(kind() | [kind()], trace()) -> trace().
events_of_kind(Kind, Events) when is_atom(Kind) ->
  events_of_kind([Kind], Events);
events_of_kind([C|_] = Kind, Events) when is_integer(C) -> % Handle strings
  events_of_kind([Kind], Events);
events_of_kind(Kinds, Events) ->
  [E || E = #{?snk_kind := Kind} <- Events, lists:member(Kind, Kinds)].

-spec projection([atom()] | atom(), trace()) -> list().
projection(Field, Trace) when is_atom(Field) ->
  [maps:get(Field, I) || I <- Trace];
projection(Fields, Trace) ->
  [list_to_tuple([maps:get(F, I) || F <- Fields]) || I <- Trace].

-spec erase_timestamps(trace()) -> trace().
erase_timestamps(Trace) ->
  [I #{?snk_meta => maps:without([time], maps:get(?snk_meta, I, #{}))} || I <- Trace].

%% @doc Find pairs of complimentary events
-spec find_pairs( boolean()
                , fun((event()) -> boolean())
                , fun((event()) -> boolean())
                , fun((event(), event()) -> boolean())
                , trace()
                ) -> [maybe_pair()].
find_pairs(Strict, CauseP, EffectP, Guard, L) ->
  Fun = fun(A) ->
            C = fun_matches1(CauseP, A),
            E = fun_matches1(EffectP, A),
            if C orelse E ->
                {true, {A, C, E}};
               true ->
                false
            end
        end,
  L1 = lists:filtermap(Fun, L),
  do_find_pairs(Strict, Guard, L1).

-spec run( run_config() | integer()
         , fun()
         , fun()
         ) -> boolean() | {error, _}.
run(Bucket, Run, Check) when is_integer(Bucket) ->
  run(#{bucket => Bucket}, Run, Check);
run(Config, Run, Check) ->
  start_trace(),
  %% Wipe the trace buffer clean:
  _ = collect_trace(0),
  snabbkaffe_collector:tp(debug, #{?snk_kind => '$trace_begin'}, #{}),
  case run_stage(Run, Config) of
    {ok, Result, Trace} ->
      try Check(Result, Trace)
      catch EC1:Error1 ?BIND_STACKTRACE(Stack1) ->
          ?GET_STACKTRACE(Stack1),
          Filename1 = dump_trace(Trace),
          logger:critical("Check stage failed: ~p~n~p~nStacktrace: ~p~n"
                          "Trace dump: ~p~n",
                          [EC1, Error1, Stack1, Filename1]),
          {error, {check_mode_failed, EC1, Error1, Stack1}}
      end;
    Err ->
      Err
  end.

-spec proper_printout(string(), list()) -> _.
proper_printout(Char, []) when Char =:= ".";
                               Char =:= "x";
                               Char =:= "!" ->
  io:put_chars(standard_error, Char);
proper_printout(Fmt, Args) ->
  logger:notice(Fmt, Args).

%%====================================================================
%% List manipulation functions
%%====================================================================

%% @doc Split list by predicate like this:
%% ```[true, true, false, true, true, false] ->
%%     [[true, true], [false, true, true], [false]]
%% '''
-spec splitr(fun((A) -> boolean()), [A]) -> [[A]].
splitr(_, []) ->
  [];
splitr(Pred, L) ->
  case lists:splitwith(Pred, L) of
    {[], [X|Rest]} ->
      {A, B} = lists:splitwith(Pred, Rest),
      [[X|A]|splitr(Pred, B)];
    {A, B} ->
      [A|splitr(Pred, B)]
  end.

%% @doc Split list by predicate like this:
%% ```[true, true, false, true, true, false] ->
%%     [[true, true, false], [true, true, false]]
%% '''
-spec splitl(fun((A) -> boolean()), [A]) -> [[A]].
splitl(_, []) ->
  [];
splitl(Pred, L) ->
  {A, B} = splitwith_(Pred, L, []),
  [A|splitl(Pred, B)].

%%====================================================================
%% CT overhauls
%%====================================================================

%% @doc Implement `all/0' callback for Common Test
-spec mk_all(module()) -> [atom() | {group, atom()}].
mk_all(Module) ->
  io:format(user, "Module: ~p", [Module]),
  Groups = try Module:groups()
           catch
             error:undef -> []
           end,
  [{group, element(1, I)} || I <- Groups] ++
  [F || {F, _A} <- Module:module_info(exports),
        case atom_to_list(F) of
          "t_" ++ _ -> true;
          _         -> false
        end].

-spec retry(integer(), non_neg_integer(), fun(() -> Ret)) -> Ret.
retry(_, 0, Fun) ->
  Fun();
retry(Timeout, N, Fun) ->
  try Fun()
  catch
    EC:Err ?BIND_STACKTRACE(Stack) ->
      ?GET_STACKTRACE(Stack),
      timer:sleep(Timeout),
      logger:debug(#{ what => retry_fun
                    , ec => EC
                    , error => Err
                    , stacktrace => Stack
                    }),
      retry(Timeout, N - 1, Fun)
  end.

-spec get_cfg([atom()], map() | proplists:proplist(), A) -> A.
get_cfg([Key|T], Cfg, Default) when is_list(Cfg) ->
  case lists:keyfind(Key, 1, Cfg) of
    false ->
      Default;
    {_, Val} ->
      case T of
        [] -> Val;
        _  -> get_cfg(T, Val, Default)
      end
  end;
get_cfg(Key, Cfg, Default) when is_map(Cfg) ->
  get_cfg(Key, maps:to_list(Cfg), Default).

-spec fix_ct_logging() -> ok.
-ifdef(OTP_RELEASE).
%% OTP21+, we have logger:
fix_ct_logging() ->
  %% Fix CT logging by overriding it
  LogLevel = case os:getenv("LOGLEVEL") of
               S when S =:= "debug";
                      S =:= "info";
                      S =:= "error";
                      S =:= "critical";
                      S =:= "alert";
                      S =:= "emergency" ->
                 list_to_atom(S);
               _ ->
                 notice
             end,
  case os:getenv("KEEP_CT_LOGGING") of
    false ->
      logger:set_primary_config(level, LogLevel),
      logger:remove_handler(default),
      logger:add_handler( default
                        , logger_std_h
                        , #{ formatter => {logger_formatter,
                                           #{ depth => 100
                                            , single_line => false
                                            , template => [time, " ", node, "\n", msg, "\n"]
                                            }}
                           }
                        );
    _ ->
      ok
  end.
-else.
fix_ct_logging() ->
  ok.
-endif.

%%====================================================================
%% Statistical functions
%%====================================================================

-spec push_stat(metric(), number()) -> ok.
push_stat(Metric, Num) ->
  snabbkaffe_collector:push_stat(Metric, undefined, Num).

-spec push_stat(metric(), number() | undefined, number()) -> ok.
push_stat(Metric, X, Y) ->
  maybe_rpc(snabbkaffe_collector, push_stat, [Metric, X, Y]).

-spec push_stats(metric(), number(), [maybe_pair()] | number()) -> ok.
push_stats(Metric, Bucket, Pairs) ->
  lists:foreach( fun(Val) -> push_stat(Metric, Bucket, Val) end
               , transform_stats(Pairs)
               ).

-spec push_stats(metric(), [maybe_pair()] | number()) -> ok.
push_stats(Metric, Pairs) ->
  lists:foreach( fun(Val) -> push_stat(Metric, Val) end
               , transform_stats(Pairs)
               ).

-spec get_stats() -> #{snabbkaffe:metric() => snabbkaffe_collector:datapoints()}.
get_stats() ->
  {ok, Stats} = gen_server:call(snabbkaffe_collector, get_stats, infinity),
  Stats.

analyze_statistics() ->
  Stats = get_stats(),
  maps:map(fun analyze_metric/2, Stats),
  ok.

%%====================================================================
%% Checks
%%====================================================================

-spec causality( boolean()
               , fun((event()) -> ok)
               , fun((event()) -> ok)
               , fun((event(), event()) -> boolean())
               , trace()
               ) -> boolean().
causality(Strict, CauseP, EffectP, Guard, Trace) ->
  Pairs = find_pairs(true, CauseP, EffectP, Guard, Trace),
  if Strict ->
      [?panic("Cause without effect", #{cause => I})
       || {singleton, I} <- Pairs];
     true ->
      ok
  end,
  length(Pairs) > 0.

-spec unique(trace()) -> true.
unique(Trace) ->
  Trace1 = erase_timestamps(Trace),
  Fun = fun(A, Acc) -> inc_counters([A], Acc) end,
  Counters = lists:foldl(Fun, #{}, Trace1),
  Dupes = [E || E = {_, Val} <- maps:to_list(Counters), Val > 1],
  case Dupes of
    [] ->
      true;
    _ ->
      ?panic("Duplicate elements found", #{dupes => Dupes})
  end.

-spec projection_complete(atom() | [atom()], trace(), [term()]) -> true.
projection_complete(Fields, Trace, Expected) ->
  Got = ordsets:from_list(projection(Fields, Trace)),
  Expected1 = ordsets:from_list(Expected),
  case ordsets:subtract(Expected1, Got) of
    [] ->
      true;
    Missing ->
      ?panic("Trace is missing elements", #{missing => Missing})
  end.

-spec projection_is_subset(atom() | [atom()], trace(), [term()]) -> true.
projection_is_subset(Fields, Trace, Expected) ->
  Got = ordsets:from_list(projection(Fields, Trace)),
  Expected1 = ordsets:from_list(Expected),
  case ordsets:subtract(Got, Expected1) of
    [] ->
      true;
    Unexpected ->
      ?panic("Trace contains unexpected elements", #{unexpected => Unexpected})
  end.

-spec pair_max_depth([maybe_pair()]) -> non_neg_integer().
pair_max_depth(Pairs) ->
  TagPair =
    fun({pair, #{?snk_meta := #{time := T1}}, #{?snk_meta := #{time := T2}}}) ->
        [{T1, 1}, {T2, -1}];
       ({singleton, #{?snk_meta := #{time := T}}}) ->
        [{T, 1}]
    end,
  L0 = lists:flatmap(TagPair, Pairs),
  L = lists:keysort(1, L0),
  CalcDepth =
    fun({_T, A}, {N0, Max}) ->
        N = N0 + A,
        {N, max(N, Max)}
    end,
  {_, Max} = lists:foldl(CalcDepth, {0, 0}, L),
  Max.

%% @doc Throws an exception when elements of the list are not strictly
%% increasing. Otherwise, returns `true' if the list is non-empty, and
%% `false' when it is empty.
%%
%% Example:
%% ```
%% SeqNums = ?projection(sequence_number, ?of_kind(handle_message, Trace)),
%% ?assert(snabbkaffe:strictly_increasing(SeqNums)),
%% '''
-spec strictly_increasing(list()) -> boolean().
strictly_increasing(L) ->
  case L of
    [Init|Rest] ->
      Fun = fun(A, B) ->
                A > B orelse
                  ?panic("Elements of list are not strictly increasing",
                         #{ '1st_element' => A
                          , '2nd_element' => B
                          , list => L
                          }),
                A
            end,
      lists:foldl(Fun, Init, Rest),
      true;
    [] ->
      false
  end.

%%====================================================================
%% Internal functions
%%====================================================================

-spec run_stage(fun(() -> Result), run_config()) -> {ok, Result, trace()}
                                                  | {run_stage_failed, atom(), _Err, _Stacktrace}.
run_stage(Run, Config) ->
  Timeout = maps:get(timeout, Config, 0),
  Bucket  = maps:get(bucket, Config, undefined),
  Trap = timetrap(Config),
  try
    Result = Run(),
    Timeout > 0 andalso logger:info("Waiting for the silence...", []),
    snabbkaffe_collector:wait_for_silence(Timeout),
    cancel_timetrap(Trap),
    Trace = snabbkaffe_collector:flush_trace(),
    RunTime = ?find_pairs( false
                         , #{?snk_kind := '$trace_begin'}
                         , #{?snk_kind := '$trace_end'}
                         , Trace
                         ),
    ?SNK_CONCUERROR orelse push_stats(run_time, Bucket, RunTime),
    {ok, Result, Trace}
  catch
    EC:Err ?BIND_STACKTRACE(Stack) ->
      ?GET_STACKTRACE(Stack),
      Trace1 = snabbkaffe_collector:flush_trace(),
      Filename = dump_trace(Trace1),
      logger:critical("Run stage failed: ~p:~p~nStacktrace: ~p~n"
                      "Trace dump: ~p~n",
                      [EC, Err, Stack, Filename]),
      {run_stage_failed, EC, Err, Stack}
  after
    cancel_timetrap(Trap),
    cleanup()
  end.

-spec do_find_pairs( boolean()
                   , fun((event(), event()) -> boolean())
                   , [{event(), boolean(), boolean()}]
                   ) -> [maybe_pair()].
do_find_pairs(_Strict, _Guard, []) ->
  [];
do_find_pairs(Strict, Guard, [{A, C, E}|T]) ->
  FindEffect = fun({B, _, true}) ->
                   fun_matches2(Guard, A, B);
                  (_) ->
                   false
               end,
  case {C, E} of
    {true, _} ->
      case take(FindEffect, T) of
        {{B, _, _}, T1} ->
          [{pair, A, B}|do_find_pairs(Strict, Guard, T1)];
        T1 ->
          [{singleton, A}|do_find_pairs(Strict, Guard, T1)]
      end;
    {false, true} when Strict ->
      ?panic("Effect occurs before cause", #{effect => A});
    _ ->
      do_find_pairs(Strict, Guard, T)
  end.

-spec dump_trace(trace()) -> file:filename().
-ifndef(CONCUERROR).
dump_trace(Trace) ->
  {ok, CWD} = file:get_cwd(),
  Filename = integer_to_list(os:system_time()) ++ ".log",
  FullPath = filename:join([CWD, "snabbkaffe", Filename]),
  filelib:ensure_dir(FullPath),
  {ok, Handle} = file:open(FullPath, [write]),
  try
    lists:foreach(fun(I) -> io:format(Handle, "~99999p.~n", [I]) end, Trace)
  after
    file:close(Handle)
  end,
  FullPath.
-else.
dump_trace(Trace) ->
  lists:foreach(fun(I) -> io:format("~99999p.~n", [I]) end, Trace).
-endif. %% CONCUERROR

-spec inc_counters([Key], Map) -> Map
        when Map :: #{Key => integer()}.
inc_counters(Keys, Map) ->
  Inc = fun(V) -> V + 1 end,
  lists:foldl( fun(Key, Acc) ->
                   maps:update_with(Key, Inc, 1, Acc)
               end
             , Map
             , Keys
             ).

-spec dec_counters([Key], Map) -> Map
        when Map :: #{Key => integer()}.
dec_counters(Keys, Map) ->
  Dec = fun(V) -> V - 1 end,
  lists:foldl( fun(Key, Acc) ->
                   maps:update_with(Key, Dec, -1, Acc)
               end
             , Map
             , Keys
             ).

-spec fun_matches1(fun((A) -> boolean()), A) -> boolean().
fun_matches1(Fun, A) ->
  try Fun(A)
  catch
    error:function_clause -> false
  end.

-spec fun_matches2(fun((A, B) -> boolean()), A, B) -> boolean().
fun_matches2(Fun, A, B) ->
  try Fun(A, B)
  catch
    error:function_clause -> false
  end.

-spec take(fun((A) -> boolean()), [A]) -> {A, [A]} | [A].
take(Pred, L) ->
  take(Pred, L, []).

take(_Pred, [], Acc) ->
  lists:reverse(Acc);
take(Pred, [A|T], Acc) ->
  case Pred(A) of
    true ->
      {A, lists:reverse(Acc) ++ T};
    false ->
      take(Pred, T, [A|Acc])
  end.

analyze_metric(MetricName, DataPoints = [N|_]) when is_number(N) ->
  %% This is a simple metric:
  Mean = mean(DataPoints),
  logger:notice("-------------------------------~n"
                "Mean ~p: ~.5f~n",
                [MetricName, Mean]);
analyze_metric(MetricName, Datapoints = [{_, _}|_]) ->
  %% This "clustering" is not scientific at all
  {XX, _} = lists:unzip(Datapoints),
  Min = lists:min(XX),
  Max = lists:max(XX),
  NumBuckets = 10,
  BucketSize = max(1, (Max - Min) div NumBuckets),
  PushBucket =
    fun({X, Y}, Acc) ->
        B0 = (X - Min) div BucketSize,
        B = Min + B0 * BucketSize,
        maps:update_with( B
                        , fun(L) -> [Y|L] end
                        , [Y]
                        , Acc
                        )
    end,
  Buckets0 = lists:foldl(PushBucket, #{}, Datapoints),
  BucketStats =
    fun({Key, Vals}) ->
        {true, {Key, mean(Vals)}}
    end,
  Buckets = lists:filtermap( BucketStats
                           , lists:keysort(1, maps:to_list(Buckets0))
                           ),
  %% Print per-bucket stats:
  PlotPoints = Buckets,
  Plot = asciiart:plot([{$*, PlotPoints}]),
  BucketStatsToString =
    fun({Key, Mean}) ->
        io_lib:format("~10b ~e~n", [Key, Mean])
    end,
  StatsStr = [ "Statisitics of ", io_lib:format("~w", [MetricName]), $\n
             , asciiart:render(Plot)
             , "\n         N    avg\n"
             , [BucketStatsToString(I) || I <- Buckets]
             ],
  logger:notice("~s~n", [StatsStr]),
  %% Print more elaborate info for the last bucket
  case length(Buckets) of
    0 ->
      ok;
    _ ->
      {_, Last} = lists:last(Buckets),
      logger:info("Stats:~n~p~n", [Last])
  end.

transform_stats(Data) ->
  Fun = fun({pair, #{?snk_meta := #{time := T1}}, #{?snk_meta := #{time := T2}}}) ->
            Dt = erlang:convert_time_unit( T2 - T1
                                         , microsecond
                                         , millisecond
                                         ),
            {true, Dt * 1.0e-6};
           (Num) when is_number(Num) ->
            {true, Num};
           (_) ->
            false
        end,
  lists:filtermap(Fun, Data).

%% @private Version of `lists:splitwith/2' that appends element that
%% doesn't match predicate to the tail of the first tuple element
splitwith_(Pred, [Hd|Tail], Taken) ->
  case Pred(Hd) of
    true  -> splitwith_(Pred, Tail, [Hd|Taken]);
    false -> {lists:reverse([Hd|Taken]), Tail}
  end;
splitwith_(_Pred, [], Taken) ->
  {lists:reverse(Taken), []}.

mean([]) ->
  0;
mean(L = [_|_]) ->
  lists:sum(L) / length(L).

get_metadata() ->
  Meta = case logger:get_process_metadata() of
            undefined -> #{};
            A -> A
          end,
  Meta #{node => node(), pid => self(), gl => group_leader()}.

-spec maybe_rpc(module(), _Function :: atom(), _Args :: list()) -> term().
maybe_rpc(M, F, A) ->
  case persistent_term:get(?PT_REMOTE, undefined) of
    undefined -> apply(M, F, A);
    Remote    -> rpc:call(Remote, M, F, A)
  end.

-spec timetrap(map()) -> pid() | undefined.
timetrap(#{timetrap := Timeout}) ->
  Parent = self(),
  spawn(
    fun() ->
        MRef = monitor(process, Parent),
        erlang:send_after(Timeout, self(), timeout),
        receive
          timeout ->
            Stack = process_info(Parent, current_stacktrace),
            Trace = collect_trace(0),
            Filename1 = dump_trace(Trace),
            logger:critical("Run stage timed out.~n"
                            "Stacktrace: ~p~n"
                            "Trace dump: ~p~n",
                            [Stack, Filename1]),
            exit(Parent, timetrap);
          {'DOWN', MRef, _, _, _} ->
            ok
        end
    end);
timetrap(_) ->
  undefined.

-spec cancel_timetrap(pid() | undefined) -> ok.
cancel_timetrap(undefined) ->
  ok;
cancel_timetrap(Pid) when is_pid(Pid) ->
  exit(Pid, kill).
