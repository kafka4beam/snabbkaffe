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
-export([next/0, fork/0]).
-export([new/1, feed/2, parse/2]).

-export_type([m/2, state/0, failed/0, parse_result/0, vertex_id/0, edge/0, edges/0]).

-compile({parse_transform, emonad}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%================================================================================
%% Type declarations
%%================================================================================

-type label() :: term().

-type vertex_id() :: non_neg_integer().

-type parser_id() :: [reference()].

-type failed() :: {parser_id(), {throw | error | exit, _Reason, _Stacktrace :: list()}}.

-type edge() ::
        #{ incident  := vertex_id() | parser_id()
         , label     := label()
         , function  := fun()
         , parser_id := parser_id()
         }.

-type edges() :: #{vertex_id() => [edge()]}.

-type parse_result() ::
        #{ complete := [{parser_id(), term()}]
         , incomplete := [parser_id()]
         , failed := [failed()]
         , vertices := #{vertex_id() => map()}
         , edges := edges()
         }.

%% Parser state:
-record(p,
        { parser_id :: parser_id()
        , prev_vertex :: vertex_id() | undefined
        , cont :: fun()
        }).

%% Global state:
-record(s,
        { counter = 1 :: vertex_id()
        , vertices = #{} :: #{vertex_id() => map()}
        , edges = #{} :: edges()
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
-spec next(label()) -> m(state(), snabbkaffe:event()).
next(Label) ->
  [do/emonad_state ||
    E <- emonad_state:consume(),
    emonad_state:return(E)].
  %% consume().
  %% [do/?MODULE ||
  %%   %% Cont <- get_cont(),
  %%   Evt <- consume(),
  %%   %% FIXME: we first update the state (which can be a rather heavy
  %%   %% operation), and only then check if event actually matches. This
  %%   %% should be optimized.
  %%   %% over_state(fun(State) ->
  %%   %%                {undefined, on_match(Cont, Label, State)}
  %%   %%            end),
  %%   return(Evt)].

%% @equiv next(undefined)
-spec next() -> m(_S, snabbkaffe:event()).
next() ->
  next(undefined).

%% @doc Clone the parser.
-spec fork() -> m(_S, undefined).
fork() ->
  [do/emonad_state ||
    S = #s{active = Active0} <- emonad_state:get_state(),
    {true, P0 = #p{parser_id = Id}} = zip_get(Active0),
    P = P0#p{parser_id = [make_ref() | Id]},
    Active = zip_insertl(P0, zip_replace(P, Active0)),
    emonad_state:put_state(S#s{active = Active})].

-spec parse(m(state(), _Result), [snabbkaffe:event()]) -> parse_result().
parse(Parser, Trace) ->
  complete(lists:foldl(fun feed/2, new(Parser), Trace)).

-spec new(_SeedParser :: m(state(), _Result)) -> state().
new(Parser) ->
  Seed = [do/?MODULE || fork(), Parser],
  {more, State, Cont} =
  #stateful{state = S, val = {more, Cont}} = Seed(#s{}),
  P = #p{ parser_id = []
        , cont      = Cont
        },
  #s{active = zip_from_list([P])}.

%% @doc Feed next event to the parser
-spec feed(snabbkaffe:event(), state()) -> state().
feed(Event, S0 = #s{counter = Incident, vertices = Vertices}) ->
  {Matched, S1} = do_feed(false, Event, S0),
  S = S1#s{ counter = Incident + 1
          , active  = zip_from_list(zip_to_list(S1#s.active))
          },
  case Matched of
    true  -> S#s{vertices = Vertices#{Incident => Event}};
    false -> S
  end.

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

zip_insertr(A, {L, R}) ->
  {L, [A|R]}.

zip_insertl(A, {L, R}) ->
  {[A|L], R}.

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

-spec do_feed(boolean(), snabbkaffe:event(), state()) -> {boolean(), state()}.
do_feed(Matched, Event, S0 = #s{active = Active0}) ->
  case zip_get(Active0) of
    false ->
      %% Reached the end of the zipper:
      {Matched, S0};
    {true, P0} ->
      {MatchedThis, S1} = feed_current(Event, S0, P0),
      S = S1#s{active = zip_shiftr(S1#s.active)},
      do_feed(Matched orelse MatchedThis, Event, S)
  end.

-spec feed_current(snabbkaffe:event(), state(), m(state(), _Ret)) -> {boolean(), state()}.
feed_current(Event, S0, #p{cont = Parser0, parser_id = ParserId}) ->
  try (Parser0(Event))(S0) of
    #stateful{state = S, val = {done, Result}} ->
      %% Parser consumed all the token it needed:
      {true, S#s{ active = zip_remove(S#s.active)
                , done   = [{ParserId, Result} | S#s.done]
                }};
    #stateful{state = S, val = {more, Parser}} ->
      %% Parser needs more tokens:
      {true, P1} = zip_get(S#s.active),
      P = P1#p{cont = Parser},
      {true, S#s{ active = zip_replace(P, S#s.active)
                }}
  catch
    {nomatch, _Event} ->
      {false, S0};
    EC:Err:Stack ->
      {true, S0#s{ active = zip_remove(S0#s.active)
                 , failed = [{ParserId, {EC, Err, Stack}} | S0#s.active]
                 }}
  end.

-spec on_match(m(state(), _Ret), label(), state()) -> state().
on_match(Cont, Label, State = #s{active = Active, counter = Incident, edges = Edges}) ->
  {true, #p{ parser_id = ParserId
           , prev_vertex = Emanent
           } = P0} = zip_get(Active),
  Edge = #{ incident => Incident
          , label => Label
          , parser_id => ParserId
          , function => Cont
          },
  P = P0#p{cont = Cont, prev_vertex = Incident},
  State#s{ edges  = add_edge(Emanent, Edges, Edge)
         , active = zip_replace(P, Active)
         }.

-spec add_edge(vertex_id(), edges(), edge()) -> edges().
add_edge(Emanent, Edges, Edge) ->
  maps:update_with(Emanent,
                   fun(EE) -> [Edge|EE] end,
                   [Edge],
                   Edges).

cont_error(State) ->
  error({cont_error, State}).

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
        A <- consume(),
        return(A)],
  S0 = state0,
  Event0 = event1,
  #stateful{state = S0, val = {more, M1}} = M(S0),
  ?assertMatch(#stateful{val = {done, Event0}, state = S0},
               (M1(Event0))(S0)).

bind_020_test() ->
  M = [do/?MODULE ||
        A <- consume(),
        C <- return(1),
        X = A + C,
        B <- consume(),
        return({X, B})],
  S0 = 0,
  #stateful{state = S1, val = {more, M1}} = M(S0),
  #stateful{state = S2, val = {more, M2}} = (M1(3))(S1),
  #stateful{state = S3, val = {done, Ret}} = (M2(2))(S1),
  ?assertMatch({4, 2}, Ret),
  ?assertMatch(S0, S3).

bind_021_test() ->
  %% Test nesting of monadic expressions:
  Rec = [do/?MODULE ||
          E <- consume(),
          return(E)],
  M = [do/?MODULE ||
        A <- Rec,
        return(A)],
  S0 = 0,
  Event = foo,
  #stateful{state = S0, val = {more, M1}} = M(S0),
  #stateful{state = S0, val = {done, Ret}} = (M1(Event))(S0),
  ?assertEqual(Event, Ret).

bind_030_test() ->
  M = [do/?MODULE ||
        A <- consume(),
        put_state([A]),
        B <- consume(),
        S <- get_state(),
        put_state([B|S]),
        return(ok)],
  S0 = [],
  #stateful{state = S0, val = {more, M1}} = M(S0),
  #stateful{state = S1 = [evt1], val = {more, M2}} = (M1(evt1))(S0),
  #stateful{state = S2 = [evt2, evt1], val = {done, ok}} = (M2(evt2))(S1).

bind_040_test() ->
  M = [do/?MODULE ||
        #{a := A} <- consume(),
        #{b := A} <- consume(),
        return(A)],
  S0 = undefined,
  #stateful{state = S0, val = {more, M1}} = M(S0),
  #stateful{state = S0, val = {more, M2}} = (M1(#{a => 1}))(S0),
  %% Matched the pattern:
  #stateful{state = S0, val = {done, 1}} = (M2(#{b => 1}))(S0),
  %% Didn't match the pattern:
  ?assertThrow({nomatch, #{b := 2}}, (M2(#{b => 2}))(S0)).

bind_050_test() ->
  M = [do/?MODULE ||
        Cont <- get_cont(),
        true = is_function(Cont, 1),
        A <- consume(),
        return(1)],
  S0 = undefined,
  #stateful{state = S0, val = {more, M1}} = M(S0),
  #stateful{state = S0, val = {done, 1}} = (M1(#{a => 1}))(S0).

feed_current_010_test() ->
  M = [do/?MODULE ||
        A <- consume(),
        B <- consume(),
        return({result, A, B})],
  %% Create new state:
  S0 = new(M),
  {true, P0} = zip_get(S0#s.active),
  %% Feed the first event:
  {true, S1} = feed_current(foo, S0, P0),
  %% Feed the second event:
  {true, P1} = zip_get(S1#s.active),
  {true, S2} = feed_current(bar, S1, P1),
  %% Check the results:
  ?assertMatch(
     #s{ done = [{_ParserId, {result, foo, bar}}]
       , active = {[], []}
       },
     S2).

feed_current_020_test() ->
  M = [do/?MODULE ||
        A <- next(foo),
        B <- next(bar),
        return({result, A, B})],
  %% Create new state:
  S0 = new(M),
  {true, P0} = zip_get(S0#s.active),
  %% Feed the first event:
  {true, S1} = feed_current(foo, S0, P0),
  %% Feed the second event:
  {true, P1} = zip_get(S1#s.active),
  {true, S2} = feed_current(bar, S1, P1),
  %% Check the results:
  ?assertMatch(
     #s{ done = [{_ParserId, {result, foo, bar}}]
       , active = {[], []}
       },
     S2).

feed_010_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- consume(),
           #{b := A} <- consume(),
           return({pair, A})],
  S0 = new(Seed),
  %% %% This event doesn't match the seed parser:
  %% S1 = feed(#{b => 1}, S0),
  %% This event matches the seed parser, add new parser to the active set
  S2 = feed(#{a => 1}, S0),
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

parse_020_fail_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(cause),
           error(deliberate)],
  Events = [#{c => 1}, #{a => 1}, #{a => 2}],
  ?assertMatch(#{ complete := []
                , incomplete := []
                , failed := [_, _]
                }, parse(Seed, Events)).

parse_030_fork_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(cause),
           fork(),
           #{b := B} <- next(effect),
           return({pair, A, B})],
  Events = [#{a => 1}, #{b => 2}, #{b => 3}, #{a => 4}, #{b => 5}],
  #{complete := Complete, incomplete := [_, _], failed := []} = parse(Seed, Events),
  {_, Results} = lists:unzip(Complete),
  ?assertMatch( [{pair, 1, 2}, {pair, 1, 3}, {pair, 1, 5}, {pair, 4, 5}]
              , lists:sort(Results)
              ).

-endif. %% TEST
