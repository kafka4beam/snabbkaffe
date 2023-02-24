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

-export_type([m/1]).

-compile({parse_transform, emonad}).

-include_lib("eunit/include/eunit.hrl").


%%================================================================================
%% Type declarations
%%================================================================================

-opaque m(R) :: {more, fun((_State, _Event) -> _Ret)}
              | {done, _Ret}
              | get_state
              | discard.

%%================================================================================
%% API funcions
%%================================================================================

-spec next() -> m(snabbkaffe:event()).
next() ->
  {more,
   fun(State, Event) ->
       Event
   end}.

-spec discard() -> m(undefined).
discard() ->
  discard.

%%================================================================================
%% behavior callbacks
%%================================================================================

-spec return(A) -> m(A).
return(A) ->
  {done, A}.

-spec bind(m(A), fun((A) -> m(B))) -> m(B).
bind({more, Cont}, Fun) ->
  {more, fun(State, Event) ->
             Val = Cont(State, Event),
             Fun(Val)
         end};
bind({done, Val}, Fun) ->
  Fun(Val);
bind(discard, _Fun) ->
  discard.

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
        , result :: m()
        }).

%% Global state:
-record(s,
        { counter = 1 :: vertex_id()
        , vertices = #{} :: #{vertex_id() => #v{}}
        , seed_parser :: m(_)
        , active :: [#p{}]
        , done :: [#p{}]
        , failed :: [#p{}]
        }).

-spec get_state() -> m(#s{}).
get_state() ->


-spec step(snabbkaffe:event(), #s{}) -> #s{}.
step(Event, S = #s{counter = Id}) ->



bind_00_test() ->
  M = [do/?MODULE ||
        A <- next(),
        return(A)],
  {more, F} = M,
  ?assertMatch({done, 1}, F(undefined, 1)).

bind_test() ->
  M = [do/?MODULE ||
        A <- next(),
        C <- return(1),
        X = A + C,
        B <- next(),
        return({X, B})],
  {more, M1} = M,
  {more, M2} = M1(undefined, 3),
  {done, Ret} = M2(undefined, 2),
  ?assertMatch({4, 2}, Ret).
