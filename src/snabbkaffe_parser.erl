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
                          {more, fun((_Event) -> s(S, R))} |
                          {done, s(S, R)}).

%%================================================================================
%% API funcions
%%================================================================================

-spec next() -> m(_S, snabbkaffe:event()).
next() ->
  fun(State) ->
      {more,
       fun(Event) ->
           #stateful{state = State, val = Event}
       end}
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
      {done, #stateful{ val = A
                      , state = S
                      }}
  end.

-spec bind(m(S, A), fun((A) -> m(S, B))) -> m(S, B).
bind(Prev, Next) ->
  fun(State0) ->
      case Prev(State0) of
        {done, #stateful{val = Val, state = State1}} ->
          (Next(Val))(State1);
        {more, Cont} ->
          {more, fun(Event) ->
                     #stateful{state = State1, val = Val} = Cont(Event),
                     (Next(Val))(State1)
                 end}
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
      {done, #stateful{val = S, state = S}}
  end.

-spec put_state(S) -> m(S, S).
put_state(S) ->
  fun(_) ->
      {done, #stateful{val = S, state = S}}
  end.

-spec step(snabbkaffe:event(), #s{}) -> #s{}.
step(Event, S = #s{counter = Id}) ->
  S.

bind_00_test() ->
  M = [do/?MODULE ||
        A <- next(),
        return(A)],
  State0 = state1,
  Event0 = event1,
  {more, M1} = M(State0),
  ?assertMatch({done, #stateful{val = Event0, state = State0}}, M1(Event0)).

bind_01_test() ->
  M = [do/?MODULE ||
        A <- next(),
        C <- return(1),
        X = A + C,
        B <- next(),
        return({X, B})],
  State0 = 0,
  {more, M1} = M(State0),
  {more, M2} = M1(3),
  {done, Ret} = M2(2),
  ?assertMatch(#stateful{val = {4, 2}, state = State0}, Ret).

bind_02_test() ->
  M = [do/?MODULE ||
        A <- next(),
        put_state([A]),
        B <- next(),
        S <- get_state(),
        put_state([B|S]),
        return(ok)],
  State0 = [],
  {more, M1} = M(State0),
  {more, M2} = M1(3),
  {done, Ret} = M2(2),
  ?assertMatch(#stateful{val = ok, state = [2, 3]}, Ret).
