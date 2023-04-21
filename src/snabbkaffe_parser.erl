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

%% Behavior callbacks:
-export([return/1, bind/2, nomatch/1]).

-export_type([m/1, state/1, failed/0, parse_result/1, vertex_id/0, edge/0, edges/0]).

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

-type parse_result(Result) ::
        #{ complete := [{parser_id(), Result}]
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
        { seed_parser
        , counter = 1
        , vertices = #{}
        , edges = #{}
        , active = {[], []}
        , done = []
        , failed = []
        }).

-opaque state(Result) ::
          #s{ seed_parser :: fun((snabbkaffe:event(), state(Result)) ->
                                    emonad_state:ret(snabbkaffe:event(), state(Result), Result))
            , counter :: vertex_id()
            , vertices :: #{vertex_id() => map()}
            , edges :: edges()
            , active :: zipper(#p{})
            , done :: [{parser_id(), Result}]
            , failed :: [failed()]
            }.

-type m(Result) :: emonad_state:t(snabbkaffe:event(), state(Result), Result).

-type cont(Result) :: fun((snabbkaffe:event(), state(Result)) ->
                             emonad_state:ret(snabbkaffe:event(), state(Result), Result)).

%%================================================================================
%% API funcions
%%================================================================================

%% @doc Suspend execution of the parser until the next token is available.
%% Return a continuation and a label
-spec next(label()) -> m(snabbkaffe:event()).
next(Label) ->
  bind(
    emonad_state:consume(),
    fun(Evt) ->
        bind(
          emonad_state:get_state(),
          fun(State) ->
              get_cont(
                fun(Cont) ->
                    bind(
                      emonad_state:put_state(on_match(Cont, Label, State)),
                      fun(_) ->
                          return(Evt)
                      end)
                end)
          end)
    end).
  %% [do/?MODULE ||
  %%   %% Cont <- get_cont(),
  %%   Evt <- emonad_state:consume(),
  %%   %% FIXME: we first update the state (which can be a rather heavy
  %%   %% operation), and only then check if event actually matches. This
  %%   %% should be optimized.
  %%   State <- emonad_state:get_state(),
  %%   emonad_state:put_state(on_match(foo, Label, State)),
  %%   return(Evt)].

%% @equiv next(undefined)
-spec next() -> m(snabbkaffe:event()).
next() ->
  next(undefined).

%% @doc Clone the parser.
-spec fork() -> m(undefined).
fork() ->
  [do/?MODULE ||
    S = #s{active = Active0, counter = Counter} <- emonad_state:get_state(),
    {true, P0 = #p{parser_id = Id}} = zip_get(Active0),
    P = P0#p{parser_id = [Counter | Id]},
    Active = zip_insertl(P0, zip_replace(P, Active0)),
    emonad_state:put_state(S#s{active = Active})].

-spec parse(m(Result), [snabbkaffe:event()]) -> parse_result(Result).
parse(Parser, Trace) ->
  complete(lists:foldl(fun feed/2, new(Parser), Trace)).

-spec new(m(Result)) -> state(Result).
new(Parser) ->
  #s{seed_parser = Parser}.

%% @doc Feed next event to the parser
-spec feed(snabbkaffe:event(), state(Result)) -> state(Result).
feed(Event, S0 = #s{counter = Incident, vertices = Vertices, seed_parser = Seed}) ->
  %% Seed the parser:
  {more, S1, SeedCont} = emonad_state:run_state(Seed, S0),
  SeedP = #p{parser_id = [Incident], cont = SeedCont},
  S2 = S1#s{active = zip_insertr(SeedP, S1#s.active)},
  %% Feed event to the active parsers:
  {Matched, S3} = do_feed(false, Event, S2),
  S = S3#s{ counter = Incident + 1
          , active  = zip_from_list(zip_to_list(S3#s.active))
          },
  case Matched of
    true  -> S#s{vertices = Vertices#{Incident => Event}};
    false -> S
  end.

%% @doc Finish parsing
-spec complete(state(Result)) -> parse_result(Result).
complete(#s{active = Active, done = Done, failed = Failed, vertices = Vertices, edges = Edges}) ->
  #{ complete   => Done
   , incomplete => [ParserId || #p{parser_id = ParserId} <- zip_to_list(Active)]
   , failed     => Failed
   , vertices   => Vertices
   , edges      => Edges
   }.

%%================================================================================
%% Behavior callbacks
%%================================================================================

bind(A, N) ->
  emonad_state:bind(A, N).

return(A) ->
  emonad_state:return(A).

nomatch(A) ->
  emonad_state:nomatch(A).

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
%% Internal functions
%%================================================================================

get_cont(Next) ->
  bind(return(Next), Next).

-spec do_feed(boolean(), snabbkaffe:event(), state(Result)) -> {boolean(), state(Result)}.
do_feed(Matched, Event, S0 = #s{active = Active0}) ->
  case zip_get(Active0) of
    false ->
      %% Reached the end of the zipper:
      {Matched, S0};
    {true, P0} ->
      {MatchedThis, S} = feed_current(Event, S0, P0),
      do_feed(Matched orelse MatchedThis, Event, S)
  end.

-spec feed_current(snabbkaffe:event(), state(Result), cont(Result)) -> {boolean(), state(Result)}.
feed_current(Event, S0, #p{cont = Cont0, parser_id = ParserId, prev_vertex = PrevVertex}) ->
  try emonad_state:feed(Cont0, S0, Event) of
    {done, S, Result} ->
      %% Parser consumed all the token it needed. Note: no `shiftr' is
      %% needed, since we removed the current item:
      {true, S#s{ active = zip_remove(S#s.active)
                , done   = [{ParserId, Result} | S#s.done]
                }};
    {more, S, Cont} ->
      %% Parser needs more tokens:
      {true, P1} = zip_get(S#s.active),
      P = P1#p{cont = Cont},
      {true, S#s{ active = zip_shiftr(zip_replace(P, S#s.active))
                }}
  catch
    {nomatch, _Event} when PrevVertex =:= undefined ->
      %% This was seed parser, we need to remove it. No shiftr is
      %% needed:
      {false, S0#s{ active = zip_remove(S0#s.active)
                  }};
    {nomatch, _Event} ->
      %% This was a matured parser, we keep it and we need to shiftr:
      {false, S0#s{ active = zip_shiftr(S0#s.active)
                  }};
    EC:Err:Stack ->
      %% Parser crashed. Add it to the list of exceptions. No shiftr is needed.
      {true, S0#s{ active = zip_remove(S0#s.active)
                 , failed = [{ParserId, {EC, Err, Stack}} | S0#s.failed]
                 }}
  end.

-spec on_match(m(Result), label(), state(Result)) -> state(Result).
on_match(Cont, Label, State = #s{active = Active, counter = Incident, edges = Edges}) ->
  {true, #p{ parser_id = ParserId
           , prev_vertex = Emanent
           } = P0} = zip_get(Active),
  Edge = #{ incident => Incident
          , label => Label
          , parser_id => ParserId
          , function => Cont
          },
  P = P0#p{prev_vertex = Incident, cont = Cont},
  State#s{ edges  = add_edge(Emanent, Edges, Edge)
         , active = zip_replace(P, Active)
         }.

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

feed_010_test() ->
  Seed = [do/?MODULE ||
           A <- emonad_state:consume(),
           B <- emonad_state:consume(),
           return({pair, A, B})],
  S0 = new(Seed),
  S2 = feed(a, S0),
  S3 = feed(b, S2),
  ?assertMatch(#{ complete := [{[1], {pair, a, b}}]
                , failed   := []
                , vertices := #{1 := _, 2 := _}
                },
               complete(S3)).

feed_011_test() ->
  Seed = [do/?MODULE ||
           A <- next(a),
           B <- next(b),
           return({pair, A, B})],
  S0 = new(Seed),
  S2 = feed(a, S0),
  S3 = feed(b, S2),
  ?assertMatch(#{ complete := [{[1], {pair, a, b}}]
                , failed   := []
                , vertices := #{1 := _, 2 := _}
                , edges    := #{1 := _}
                },
               complete(S3)).

feed_012_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(a),
           #{b := B} <- next(b),
           return({pair, A, B})],
  S0 = new(Seed),
  S1 = feed(#{a => a}, S0),
  S2 = feed(#{x => x}, S1),
  S3 = feed(#{b => b}, S2),
  ?assertMatch(#{ complete   := [{[1], {pair, a, b}}]
                , incomplete := []
                , failed     := []
                , vertices   := #{1 := _, 3 := _}
                , edges      := #{1 := _}
                },
               complete(S3)).

parse_010_test() ->
  Seed = [do/?MODULE ||
           #{a := A} <- next(cause),
           #{b := A} <- next(effect),
           return({pair, A})],
  Events = [#{c => 1}, #{b => 2}, #{a => 1}, #{a => 2}, #{c => 1}, #{b => 2}, #{b => 1}, #{a => 3}],
  ?assertMatch(#{ complete := [{[3], {pair, 1}}, {[4], {pair, 2}}]
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
                , failed := [ {[3], {error, deliberate, _}}
                            , {[2], {error, deliberate, _}}
                            ]
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
