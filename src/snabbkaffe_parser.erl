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

-type cont(A, R) :: fun((fun((A) -> R)) -> R).

-opaque m(R) :: cont(snabbkaffe:event(), R).

%% -type vertex_id() :: snabbkaffe:event().

%% %% Vertex:
%% -record(connector,
%%         { emanent :: vertex_id()
%%         , cont ::
%%         }).

%% %% Parser state:
%% -record(s,
%%         { result :: term()
%%         , graph :: digraph:graph()
%%         , active_set :: []
%%         }).

%% -opaque m(_A) :: #s{}.

%%================================================================================
%% API funcions
%%================================================================================

-spec next() -> m(snabbkaffe:event()).
next() ->
  {more, fun(State, Event) ->
             Event
         end}.

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
  Fun(Val).

nomatch(A) ->
  throw({nomatch, A}).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

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
