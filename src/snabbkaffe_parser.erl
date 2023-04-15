%%--------------------------------------------------------------------
%% Copyright (c) 2023 EMQ Technologies Co., Ltd. All Rights Reserved.
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
-export([new/1, feed/2, parse/2]).

%% behavior callbacks:
-export([bind/2, return/1, nomatch/1]).

-export_type([m/2, state/0, parse_result/0, vertex_id/0, edge/0, edges/0]).

-compile({parse_transform, emonad}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%================================================================================
%% Type declarations
%%================================================================================

-record(stateful, {val, state}).

-type s(S, R) :: #stateful{val :: R, state :: S}.

-opaque m(S, R) :: fun((S) ->
                          s(S, {more, fun((_Event) -> m(S, R))} |
                               {done, R})).

-type label() :: term().

-type vertex_id() :: non_neg_integer().

-type parser_id() :: [reference()].

-type edge() ::
        #{ incident  := vertex_id()
         , label     := label()
         , function  := fun()
         , parser_id := parser_id()
         }.

-type edges() :: #{vertex_id() => [edge()]}.

-type parse_result() ::
        #{ complete := [{parser_id(), term()}]
         , incomplete := [parser_id()]
         , failed := [{ parser_id()
                      , {_ErrorKind :: throw | error | exit, _Error :: term(), _Stacktrace :: list()}
                      }]
         , vertices := #{vertex_id() => snabbkaffe:event()}
         , edges := edges()
         }.

%% Vertex
-record(v,
        { event :: snabbkaffe:event()
        }).

%% Parser state:
-record(p,
        { parser_id :: parser_id()
        , prev_vertex :: vertex_id() | undefined
        , cont :: m(_, _)
        , label :: label()
        }).

%% Global state:
-record(s,
        { counter = 1 :: vertex_id()
        , vertices = #{} :: #{vertex_id() => #v{}}
        , edges = #{} :: edges()
        , seed_parser :: m(_, _)
        , active = {[], []} :: zipper(#p{})
        , done = [] :: [{vertex_id(), term()}]
        , failed = [] :: [#p{}]
        }).

-opaque state() :: #s{}.

%%================================================================================
%% API funcions
%%================================================================================

%% @doc Suspend execution of the parser until the next token is available.
%% Return a continuation and a label
-spec next(term()) -> m(_S, snabbkaffe:event()).
next(Label) ->
  fun(State) ->
      #stateful{ state = State
               , val = {more, Label, fun(Event) -> Event end}
               }
  end.

%% @equiv next(undefined)
-spec next() -> m(_S, snabbkaffe:event()).
next() ->
  next(undefined).

%% @doc Create a new outgoing edge from the current vertex
-spec fork() -> m(_S, undefined).
fork() ->
  over_state(fun(S = #s{active = Active0}) ->
                 {true, Parser0 = #p{parser_id = Id}} = zip_get(Active0),
                 Parser1 = Parser0#p{parser_id = [make_ref()|Id]},
                 Parser2 = Parser0#p{parser_id = [make_ref()|Id]},
                 Active = zip_replace(Parser1, zip_shiftr(zip_insert(Parser2, Active0))),
                 {undefined, S#s{active = Active}}
             end).

-spec parse(m(state(), _Result), [snabbkaffe:event()]) -> parse_result().
parse(Parser, Trace) ->
  complete(lists:foldl(fun feed/2, new(Parser), Trace)).

-spec new(_SeedParser :: m(state(), _Result)) -> state().
new(Seed) ->
  #s{seed_parser = Seed}.

%% @doc Feed next event to the parser
-spec feed(snabbkaffe:event(), state()) -> state().
feed(Event, S0 = #s{counter = Id, vertices = V0, seed_parser = Seed}) ->
  S1 = S0#s{vertices = V0#{Id => Event}},
  %% Seed and feed:
  #stateful{state = S2, val = {more, SeedLabel, Seed1}} = Seed(S1),
  P = #p{ cont = Seed1
        , label = SeedLabel
        , parser_id = [make_ref()]
        },
  S4 = case feed_current(Event, S2, P) of
         {done, Done, S3 = #s{done = Done0}, _Edge} ->
           S3#s{done = [Done | Done0]};
         {more, Next, S3 = #s{active = Active0}, _Edge} ->
           S3#s{active = zip_shiftr(zip_insert(Next, Active0))};
         nomatch ->
           S1
       end,
  %% Process the existing parsers:
  S = #s{active = Active} = do_feed(Event, S4),
  S#s{ active = zip_from_list(zip_to_list(Active))
     , counter = Id + 1
     }.

%% @doc Finish parsing
-spec complete(state()) -> parse_result().
complete(#s{active = Active, done = Done, failed = Failed, vertices = Vertices, edges = Edges}) ->
  #{ complete => Done
   , incomplete => [ParserId || #p{parser_id = ParserId} <- zip_to_list(Active)]
   , failed => Failed
   , vertices => Vertices
   , edges => Edges
   }.

%%================================================================================
%% Zippers
%%================================================================================

-type zipper(A) :: {[A], [A]}.

zip_get({_, [A|_]}) ->
  {true, A};
zip_get({_, []}) ->
  false.

zip_remove({L, [_|R]}) ->
  {L, R}.

zip_replace(A, {L, [_|R]}) ->
  {L, [A|R]}.

zip_insert(A, {L, R}) ->
  {L, [A|R]}.

zip_shiftl({[A|L], R}) ->
  {L, [A|R]};
zip_shiftl(Z) ->
  Z.

zip_shiftr({L, [A|R]}) ->
  {[A|L], R};
zip_shiftr(Z) ->
  Z.

zip_from_list(L) ->
  {[], L}.

zip_to_list({L, R}) ->
  lists:reverse(L) ++ R.

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
        #stateful{val = {more, Label, Cont}, state = State1} ->
          More = fun(Event) ->
                     fun(State2) ->
                         Val = Cont(Event),
                         (Next(Val))(State2)
                     end
                 end,
          #stateful{ state = State1
                   , val = {more, Label, More}
                   }
      end
  end.

nomatch(A) ->
  throw({nomatch, A}).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

%% @private Low level API that returns parser state
-spec get_state() -> m(S, S).
get_state() ->
  fun(S) ->
      #stateful{val = {done, S}, state = S}
  end.

%% @private Low level API that modifies parser state
-spec put_state(S) -> m(S, S).
put_state(S) ->
  fun(_) ->
      #stateful{val = {done, S}, state = S}
  end.

-spec over_state(fun((S) -> {A, S})) -> m(S, A).
over_state(Fun) ->
  fun(S0) ->
      {Val, State} = Fun(S0),
      #stateful{val = {done, Val}, state = State}
  end.

-spec do_feed(snabbkaffe:event(), #s{}) -> #s{}.
do_feed(Event, S0 = #s{active = Active0}) ->
  case zip_get(Active0) of
    false ->
      S0;
    {true, Parser = #p{prev_vertex = Emanent}} ->
      S = case feed_current(Event, S0, Parser) of
            {done, Result, S1 = #s{active = Active, done = Results, edges = Edges}, NewEdge} ->
              S1#s{ active = zip_remove(Active)
                  , done   = [Result | Results]
                  , edges  = add_edge(Emanent, Edges, NewEdge)
                  };
            {more, Next, S1 = #s{active = Active, edges = Edges}, NewEdge} ->
              S1#s{ active = zip_replace(Next, Active)
                  , edges  = add_edge(Emanent, Edges, NewEdge)
                  };
            nomatch ->
              S0
          end,
      do_feed(Event, S#s{active = zip_shiftr(S#s.active)})
  end.

-spec feed_current(snabbkaffe:event(), #s{}, #p{}) -> {more, #p{}, #s{}, edge()}
                                                    | {done, _Result, #s{}, edge()}
                                                    | nomatch.
feed_current(Event,
             State0 = #s{active = Active0, counter = Counter},
             #p{ cont = Parser0
               , label = Label
               , parser_id = ParserId
               , prev_vertex = PrevVertex
               }) ->
  Edge = #{ incident => Counter
          , label => Label
          , function => Parser0
          , parser_id => ParserId
          },
  try (Parser0(Event))(State0) of
    #stateful{state = State, val = {done, Result}} ->
      %% Parser completed:
      Done = {ParserId, Result},
      {done, Done, State, Edge};
    #stateful{state = State, val = {more, NextLabel, Parser}} ->
      %% Parser waits for the next token:
      More = #p{ cont = Parser
               , label = NextLabel
               , prev_vertex = Counter
               , parser_id = ParserId
               },
      {more, More, State, Edge}
  catch {nomatch, _Nomatch} ->
      nomatch
  end.

-spec add_edge(vertex_id(), edges(), edge()) -> edges().
add_edge(Emanent, Edges, Edge) ->
  maps:update_with(Emanent,
                   fun(EE) -> [Edge|EE] end,
                   [Edge],
                   Edges).

%%================================================================================
%% Testcases
%%================================================================================

-ifdef(TEST).

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
        A <- next(label1),
        return(A)],
  S0 = state0,
  Event0 = event1,
  #stateful{state = S0, val = {more, label1, M1}} = M(S0),
  ?assertMatch(#stateful{val = {done, Event0}, state = S0},
               (M1(Event0))(S0)).

bind_020_test() ->
  M = [do/?MODULE ||
        A <- next(label1),
        C <- return(1),
        X = A + C,
        B <- next(),
        return({X, B})],
  S0 = 0,
  #stateful{state = S1, val = {more, label1, M1}} = M(S0),
  #stateful{state = S2, val = {more, undefined, M2}} = (M1(3))(S1),
  #stateful{state = S3, val = {done, Ret}} = (M2(2))(S1),
  ?assertMatch({4, 2}, Ret),
  ?assertMatch(S0, S3).

bind_030_test() ->
  M = [do/?MODULE ||
        A <- next(label1),
        put_state([A]),
        B <- next(),
        S <- get_state(),
        put_state([B|S]),
        return(ok)],
  S0 = [],
  #stateful{state = S0, val = {more, label1, M1}} = M(S0),
  #stateful{state = S1 = [evt1], val = {more, undefined, M2}} = (M1(evt1))(S0),
  #stateful{state = S2 = [evt2, evt1], val = {done, ok}} = (M2(evt2))(S1).

bind_040_test() ->
  M = [do/?MODULE ||
        #{a := A} <- next(),
        #{b := A} <- next(),
        return(A)],
  S0 = undefined,
  #stateful{state = S0, val = {more, undefined, M1}} = M(S0),
  #stateful{state = S0, val = {more, undefined, M2}} = (M1(#{a => 1}))(S0),
  %% Matched the pattern:
  #stateful{state = S0, val = {done, 1}} = (M2(#{b => 1}))(S0),
  %% Didn't match the pattern:
  ?assertThrow({nomatch, #{b := 2}}, (M2(#{b => 2}))(S0)).

feed_010_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(cause),
           #{b := A} <- next(effect),
           return({pair, A})],
  S0 = new(Seed),
  %% This event doesn't match the seed parser:
  S1 = feed(#{b => 1}, S0),
  %% This event matches the seed parser, add new parser to the active set:
  S2 = feed(#{a => 1}, S1),
  S3 = feed(#{b => 1}, S2),
  ?assertMatch(#{ complete := [{[_Ref], {pair, 1}}]
                , incomplete := []
                , failed := []
                , vertices := #{}
                , edges := #{2 := [_]}
                },
               complete(S3)).

parse_010_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(cause),
           #{b := A} <- next(effect),
           return({pair, A})],
  Events = [#{c => 1}, #{b => 2}, #{a => 1}, #{a => 2}, #{c => 1}, #{b => 2}, #{b => 1}, #{a => 3}],
  ?assertMatch(#{ complete := [{[_Ref1], {pair, 1}}, {[_Ref2], {pair, 2}}]
                , incomplete := [_]
                , failed := []
                }, parse(Seed, Events)).

-endif. %% TEST
