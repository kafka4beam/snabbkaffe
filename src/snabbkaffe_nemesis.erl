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

%% @doc This module implements "nemesis" process that injects faults
%% into system under test in order to test its fault-tolerance.
%%
%% == Usage ==
%%
%% === Somewhere in the tested code ===
%%
%% ```
%% ?maybe_crash(kind1, #{data1 => Foo, field2 => Bar})
%% '''
%%
%% === Somewhere in the run stage ===
%%
%% ```
%% ?inject_crash( #{?snk_kind := kind1, data1 := 42}
%%              , snabbkaffe_nemesis:always_crash()
%%              )
%% '''
%% @end
-module(snabbkaffe_nemesis).

-include("snabbkaffe_internal.hrl").

-behaviour(gen_server).

%% API
-export([ start_link/0
        , inject_crash/2
        , inject_crash/3
        , fix_crash/1
        , cleanup/0
        , maybe_crash/2
          %% Delay
        , force_ordering/3
        , maybe_delay/1
          %% Failure scenarios
        , always_crash/0
        , recover_after/1
        , random_crash/1
        , periodic_crash/3
        ]).

-export_type([fault_scenario/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2]).

-define(SERVER, ?MODULE).

-define(ERROR_TAB, snabbkaffe_injected_errors).
-define(STATE_TAB, snabbkaffe_fault_states).
-define(DELAY_TAB, snabbkaffe_injected_delays).
-define(SINGLETON_KEY, 0).

%%%===================================================================
%%% Types
%%%===================================================================

%% @doc
%% Type of fault patterns, such as "always fail", "fail randomly" or
%% "recover after N attempts"
%% @end
%%
%% This type is pretty magical. For performance reasons, state of the
%% failure scenario is encoded as an integer counter, that is
%% incremented every time the scenario is run. (BEAM VM can do this
%% atomically and fast). Therefore "failure scenario" should map
%% integer to boolean.
-opaque fault_scenario() :: fun((integer()) -> boolean()).

-type fault_key() :: term().

%% State of failure point (it's a simple counter, see above comment):
%-type fault_state() :: {fault_key(), integer()}.

%% Injected error:
-record(fault,
        { reference :: reference()
        , predicate :: snabbkaffe:predicate()
        , scenario  :: snabbkaffe:fault_scenario()
        , reason    :: term()
        }).

%% Injected delay:
-record(delay,
        { reference          :: reference()
        , delay_predicate    :: snabbkaffe:predicate()  % Event that is being delayed
        , continue_predicate :: snabbkaffe:predicate2() % Event that unlocks execution of the delayed process
        , n_events           :: non_neg_integer()
        }).

%% Currently this gen_server just holds the ets tables and
%% synchronizes writes to the fault table, but in the future it may be
%% used to mess up the system in more interesting ways
-record(s,
        { injected_errors :: ets:tid()
        , fault_states    :: ets:tid()
        , injected_delays :: ets:tid()
        }).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the server
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @equiv inject_crash(Predicate, Scenario, notmyday)
-spec inject_crash(snabbkaffe:predicate(), fault_scenario()) -> reference().
inject_crash(Predicate, Scenario) ->
  inject_crash(Predicate, Scenario, notmyday).

%% @doc Inject crash into the system
-spec inject_crash(snabbkaffe:predicate(), fault_scenario(), term()) -> reference().
inject_crash(Predicate, Scenario, Reason) ->
  Ref = make_ref(),
  Crash = #fault{ reference = Ref
                , predicate = Predicate
                , scenario  = Scenario
                , reason    = Reason
                },
  ok = gen_server:call(?SERVER, {inject_crash, Crash}, infinity),
  Ref.

%% @doc Remove injected fault
-spec fix_crash(reference()) -> ok.
fix_crash(Ref) ->
  gen_server:call(?SERVER, {fix_crash, Ref}, infinity).

%% @doc Remove all injected crashes
-spec cleanup() -> ok.
cleanup() ->
  gen_server:call(?SERVER, cleanup, infinity).

%% @doc Check if there are any injected crashes that match this data,
%% and respond with the crash reason if so.
-spec maybe_crash(fault_key(), map()) -> ok.
maybe_crash(Key, Data) ->
  [begin
     NewVal = ets:update_counter(?STATE_TAB, Key, {2, 1}, {Key, 0}),
     %% Run fault_scenario function to see if we need to crash this
     %% time:
     case S(NewVal) of
       true ->
         snabbkaffe_collector:tp( debug
                                , Data#{ crash_kind => Key
                                       , ?snk_kind  => snabbkaffe_crash
                                       }
                                , #{}
                                ),
         exit(R);
       false ->
         ok
     end
   end
   || {_, Faults} <- lookup_singleton(?ERROR_TAB),
      #fault{ scenario  = S
            , reason    = R
            , predicate = Pred
            } <- Faults,
      Pred(Data)],
  ok.

%% @doc Inject delay into the system
-spec force_ordering(snabbkaffe:predicate(), non_neg_integer(), snabbkaffe:predicate2()) -> reference().
force_ordering(DelayPredicate, NEvents, ContinuePredicate) when NEvents > 0 ->
  Ref = make_ref(),
  Delay = #delay{ reference          = Ref
                , delay_predicate    = DelayPredicate
                , continue_predicate = ContinuePredicate
                , n_events           = NEvents
                },
  ok = gen_server:call(?SERVER, {force_ordering, Delay}, infinity),
  Ref.

%% @doc Check if the trace point should be delayed.
-spec maybe_delay(map()) -> ok.
maybe_delay(Event) ->
  [snabbkaffe_collector:block_until( {fun(WU) -> ContP(Event, WU) end, NEvents}
                                   , infinity
                                   , infinity
                                   )
   || {_, Delays} <- lookup_singleton(?DELAY_TAB),
      #delay{ continue_predicate = ContP
            , delay_predicate    = DelayP
            , n_events           = NEvents
            } <- Delays,
      DelayP(Event)],
  ok.

%%%===================================================================
%%% Fault scenarios
%%%===================================================================

-spec always_crash() -> fault_scenario().
always_crash() ->
  fun(_) ->
      true
  end.

-spec recover_after(non_neg_integer()) -> fault_scenario().
recover_after(Times) ->
  fun(X) ->
      X =< Times
  end.

-spec random_crash(float()) -> fault_scenario().
random_crash(CrashProbability) ->
  fun(X) ->
      Range = 2 bsl 16,
      %% Turn a sequential number into a sufficiently plausible
      %% pseudorandom one:
      Val = erlang:phash2(X, Range),
      Val < CrashProbability * Range
  end.

%% @doc A type of fault that occurs and fixes periodically.
-spec periodic_crash(integer(), float(), float()) -> fault_scenario().
periodic_crash(Period, DutyCycle, Phase) ->
  DC = DutyCycle * Period,
  P = round(Phase/(math:pi()*2)*Period),
  fun(X) ->
      (X + P - 1) rem Period >= DC
  end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
  ST = ets:new(?STATE_TAB, [ named_table
                           , {write_concurrency, true}
                           , {read_concurrency, true}
                           , public
                           ]),
  FT = ets:new(?ERROR_TAB, [ named_table
                           , {write_concurrency, false}
                           , {read_concurrency, true}
                           , protected
                           ]),
  DT = ets:new(?DELAY_TAB, [ named_table
                           , {write_concurrency, false}
                           , {read_concurrency, true}
                           , public
                           ]),
  init_data(),
  {ok, #s{ injected_errors = FT
         , fault_states    = ST
         , injected_delays = DT
         }}.

%% @private
handle_call({inject_crash, Crash}, _From, State) ->
  [{_, Faults}] = ets:lookup(?ERROR_TAB, ?SINGLETON_KEY),
  ets:insert(?ERROR_TAB, {?SINGLETON_KEY, [Crash|Faults]}),
  {reply, ok, State};
handle_call({fix_crash, Ref}, _From, State) ->
  [{_, Faults0}] = ets:lookup(?ERROR_TAB, ?SINGLETON_KEY),
  Faults = lists:keydelete(Ref, #fault.reference, Faults0),
  ets:insert(?ERROR_TAB, {?SINGLETON_KEY, Faults}),
  {reply, ok, State};
handle_call({force_ordering, Delay}, _From, State) ->
  [{_, Delays}] = ets:lookup(?DELAY_TAB, ?SINGLETON_KEY),
  ets:insert(?DELAY_TAB, {?SINGLETON_KEY, [Delay|Delays]}),
  {reply, ok, State};
handle_call(cleanup, _From, State) ->
  ets:delete_all_objects(?ERROR_TAB),
  ets:delete_all_objects(?DELAY_TAB),
  ets:delete_all_objects(?STATE_TAB),
  init_data(),
  {reply, ok, State};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%% @private
handle_cast(_Request, State) ->
  {noreply, State}.

%% @private
handle_info(_Info, State) ->
  {noreply, State}.

%% @private
terminate(_Reason, _State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec lookup_singleton(atom()) -> [{?SINGLETON_KEY, term()}].
lookup_singleton(Table) ->
  try ets:lookup(Table, ?SINGLETON_KEY) of
    Val -> Val
  catch
    error:badarg ->
      %% Table doesn't exist. Probably it happens because snabbkaffe
      %% nemesis was stopped while the SUT is running. Ignore it and
      %% let the SUT do its thing.
      []
  end.

-spec init_data() -> ok.
init_data() ->
  ets:insert(?ERROR_TAB, {?SINGLETON_KEY, []}),
  ets:insert(?DELAY_TAB, {?SINGLETON_KEY, []}),
  ok.
