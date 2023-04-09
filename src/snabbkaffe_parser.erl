%%--------------------------------------------------------------------
%% Copyright (c) 2022-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
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
%%--------------------------------------------------------------------
-module(snabbkaffe_parser).

-behavior(emonad).

%% API:
-export([next/0]).

%% behavior callbacks:
-export([bind/2, return/1, nomatch/1]).

-export_type([m/2]).

-compile({parse_transform, emonad}).

-include_lib("eunit/include/eunit.hrl").


%%================================================================================
%% Type declarations
%%================================================================================

-record(stateful, {val, state}).

-type s(S, R) :: #stateful{val :: R, state :: S}.

-opaque m(S, R) :: fun((S) ->
                          s(S, {more, fun((_Event) -> m(S, R))} |
                               {done, R})).

%%================================================================================
%% API funcions
%%================================================================================

-spec next() -> m(_S, snabbkaffe:event()).
next() ->
  fun(State) ->
      #stateful{ state = State
               , val = {more, fun(Event) ->
                                  Event
                              end}
               }
  end.

%% -spec discard() -> m(undefined).
%% discard() ->
%%   discard.

%%================================================================================
%% behavior callbacks
%%================================================================================

-spec return(A) -> m(_S, A).
return(A) ->
  fun(S) ->
      #stateful{ state = S
               , val = {done, A}
               }
  end.

-spec bind(m(S, A), fun((A) -> m(S, B))) -> m(S, B).
bind(Prev, Next) ->
  fun(State0) ->
      case Prev(State0) of
        #stateful{val = {done, Val}, state = State1} ->
          (Next(Val))(State1);
        #stateful{val = {more, Cont}, state = State1} ->
          More = fun(Event) ->
                     fun(State2) ->
                         Val = Cont(Event),
                         (Next(Val))(State2)
                     end
                 end,
          #stateful{ state = State1
                   , val = {more, More}
                   }
      end
  end.

%% -spec bind(m(A), fun((A) -> m(B))) -> m(B).
%% bind({more, Cont}, Next) ->
%%   {more, fun(State, Event) ->
%%              Val = Cont(State, Event),
%%              Next(Val)
%%          end};
%% bind({done, Val}, Next) ->
%%   Next(Val).

nomatch(A) ->
  throw({nomatch, A}).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

-type vertex_id() :: non_neg_integer().

%% Vertex
-record(v,
        { event :: snabbkaffe:event()
        }).

%% Parser state:
-record(p,
        { visited :: [vertex_id()]
        , result :: m(_, _)
        }).

%% Global state:
-record(s,
        { counter = 1 :: vertex_id()
        , vertices = #{} :: #{vertex_id() => #v{}}
        , seed_parser :: m(_, _)
        , active :: [#p{}]
        , done :: [#p{}]
        , failed :: [#p{}]
        }).

-spec get_state() -> m(S, S).
get_state() ->
  fun(S) ->
      #stateful{val = {done, S}, state = S}
  end.

-spec put_state(S) -> m(S, S).
put_state(S) ->
  fun(_) ->
      #stateful{val = {done, S}, state = S}
  end.

-spec step(snabbkaffe:event(), #s{}) -> #s{}.
step(Event, S = #s{counter = Id}) ->
  S.

bind_000_test() ->
  M = [do/?MODULE ||
        return(1),
        return(2)],
  S0 = state0,
  ?assertMatch(#stateful{state = S0, val = {done, 2}}, M(S0)).

bind_001_test() ->
  M = [do/?MODULE ||
        S0 <- get_state(),
        put_state(1),
        S1 <- get_state(),
        put_state(2),
        S2 <- get_state(),
        return({S0, S1, S2})],
  S0 = 0,
  ?assertMatch(#stateful{state = 2, val = {done, {0, 1, 2}}}, M(S0)).

bind_010_test() ->
  M = [do/?MODULE ||
        A <- next(),
        return(A)],
  S0 = state0,
  Event0 = event1,
  #stateful{state = S0, val = {more, M1}} = M(S0),
  ?assertMatch(#stateful{val = {done, Event0}, state = S0},
               (M1(Event0))(S0)).

bind_020_test() ->
  M = [do/?MODULE ||
        A <- next(),
        C <- return(1),
        X = A + C,
        B <- next(),
        return({X, B})],
  S0 = 0,
  #stateful{state = S1, val = {more, M1}} = M(S0),
  #stateful{state = S2, val = {more, M2}} = (M1(3))(S1),
  #stateful{state = S3, val = {done, Ret}} = (M2(2))(S1),
  ?assertMatch({4, 2}, Ret),
  ?assertMatch(S0, S3).

bind_030_test() ->
  M = [do/?MODULE ||
        A <- next(),
        put_state([A]),
        B <- next(),
        S <- get_state(),
        put_state([B|S]),
        return(ok)],
  S0 = [],
  #stateful{state = S0, val = {more, M1}} = M(S0),
  #stateful{state = S1 = [evt1], val = {more, M2}} = (M1(evt1))(S0),
  #stateful{state = S2 = [evt2, evt1], val = {done, ok}} = (M2(evt2))(S1).
