%% Copyright 2024 snabbkaffe contributors
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

%% @doc This module contains helper functions for diffing large Erlang lists.
%%
%% It tries to limit the amount of information returned to the user.
-module(snabbkaffe_diff).

%% API:
-export([diff_lists/3, format/1, assert_lists_eq/2, assert_lists_eq/3]).

-export_type([cfun/2, options/0, diff/2]).

%%================================================================================
%% Type declarations
%%================================================================================

%% Stream can be either an ordinary list, or an improper list with
%% function as a tail, that produces more elements, a.k.a stream.
%%
%% WARNING: the user must make sure streams are finite!
-type stream(A) :: maybe_improper_list(A, [] | fun(() -> stream(A))).

-record(context,
        { size :: non_neg_integer()
        , n = 0 :: non_neg_integer()
        , head :: queue:queue(A)
        , tail :: queue:queue(A)
        }).

-type context(_A) :: #context{}.

-type diff(A, B) :: {extra, B} | {missing, A} | {changed, A, B} | {ctx, B} | binary().

-type diff_(A, B) :: {extra, B} | {missing, A} | {changed, A, B} | {ctx, context(A), context(B)}.

-record(s,
        { ctx1 :: context(A)
        , ctx2 :: context(B)
        , n_failures = 0 :: non_neg_integer()
        , failures :: context([diff_(A, B)])
        , window :: pos_integer()
        }).

-type cfun(A, B) :: fun((A, B) -> boolean()).

-type options() ::
        #{ compare_fun => cfun(_A, _B)       % Function used for element comparision
         , max_failures => non_neg_integer() % Limit the number differences returned
         , context => non_neg_integer()      % Add N elements around each difference
         , window => pos_integer()           % Look ahead when detecting skips
         , comment => term()
         }.

%%================================================================================
%% API functions
%%================================================================================

-spec assert_lists_eq(stream(_A), stream(_B)) -> ok.
assert_lists_eq(A, B) ->
  assert_lists_eq(A, B, #{}).

-spec assert_lists_eq(stream(_A), stream(_B), options()) -> ok.
assert_lists_eq(A, B, Options) ->
  case diff_lists(Options, A, B) of
    [] ->
      ok;
    Fails ->
      logger:error("Lists are not equal:~n~s", [format(Fails)]),
      error({lists_not_equal, maps:get(comment, Options, "")})
  end.

-spec format(diff(_A, _B) | [diff(_A, _B)]) -> iolist().
format({ctx, Bin}) when is_binary(Bin) ->
  <<Bin / binary, "\n">>;
format({ctx, Term}) ->
  io_lib:format( "      ~0p~n"
               , [Term]
               );
format({extra, Term}) ->
  io_lib:format( "!! ++ ~0p~n"
               , [Term]
               );
format({missing, Term}) ->
  io_lib:format( "!! -- ~0p~n"
               , [Term]
               );
format({changed, T1, T2}) ->
  io_lib:format( "!! -  ~0p~n"
                 "!! +  ~0p~n"
               , [T1, T2]
               );
format(L) when is_list(L) ->
  lists:map(fun format/1, L).

-spec diff_lists(options(), stream(A), stream(B)) -> [diff(A, B)].
diff_lists(Custom, A, B) ->
  Default = #{ compare_fun => fun(X, Y) -> X =:= Y end
             , context => 5
             , max_failures => 10
             , window => 100
             },
  #{ compare_fun := CFun
   , context := CtxSize
   , max_failures := MaxFailures
   , window := Window
   } = maps:merge(Default, Custom),
  S = go(CFun, A, B,
         #s{ ctx1 = ctx_new(CtxSize)
           , ctx2 = ctx_new(CtxSize)
           , failures = ctx_new(MaxFailures)
           , window = Window
           }),
  #s{ctx1 = Ctx1, ctx2 = Ctx2, n_failures = NFails, failures = Fails0} = S,
  Fails = lists:flatten([ctx_to_list(Fails0), {ctx, Ctx1, Ctx2}]),
  case NFails of
    0 ->
      [];
    _ ->
      lists:flatmap(fun(Bin) when is_binary(Bin) -> [{ctx, Bin}];
                       ({ctx, _C1, C2})          -> [{ctx, I} || I <- ctx_to_list(C2)];
                       (Diff)                    -> [Diff]
                    end,
                    Fails)
  end.

%%================================================================================
%% Internal functions
%%================================================================================

go(CFun, Fa, B, S) when is_function(Fa, 0) ->
  go(CFun, Fa(), B, S);
go(CFun, A, Fb, S) when is_function(Fb, 0) ->
  go(CFun, A, Fb(), S);
go(_CFun, [], [], S) ->
  S;
go(CFun, [Ha | A], [], S0) ->
  S = fail({missing, Ha}, S0),
  go(CFun, A, [], S);
go(CFun, [], [Hb | B], S0) ->
  S = fail({extra, Hb}, S0),
  go(CFun, [], B, S);
go(CFun, [Ha | A], [Hb | B], S0 = #s{ctx1 = Ctx1, ctx2 = Ctx2}) ->
  case CFun(Ha, Hb) of
    true ->
      S = S0#s{ ctx1 = ctx_push(Ha, Ctx1)
              , ctx2 = ctx_push(Hb, Ctx2)
              },
      go(CFun, A, B, S);
    false ->
      {S, A1, B1} = detect_fail(CFun, [Ha | A], [Hb | B], S0),
      go(CFun, A1, B1, S)
  end.

fail(Fail, S = #s{n_failures = NFailures, failures = Fails, ctx1 = Ctx1, ctx2 = Ctx2}) ->
  S#s{ n_failures = NFailures + 1
     , failures = ctx_push([{ctx, Ctx1, Ctx2}, Fail], Fails)
     , ctx1 = ctx_drop(Ctx1)
     , ctx2 = ctx_drop(Ctx2)
     }.

detect_fail(CFun, [Ha | A], [Hb | B], S0 = #s{window = Window}) ->
  %% Extremely stupid greedy algorithm is used here.
  ScoreA = score(CFun, Ha, B, Window),
  ScoreB = score(CFun, Hb, A, Window),
  if ScoreA =:= ScoreB ->
      { fail({changed, Ha, Hb}, S0)
      , A
      , B
      };
     ScoreA > ScoreB ->
      { fail({extra, Hb}, S0)
      , [Ha | A]
      , B
      };
     ScoreA < ScoreB ->
      { fail({missing, Ha}, S0)
      , A
      , [Hb | B]
      }
  end.

-spec score(cfun(A, B), A, stream(B), non_neg_integer()) -> non_neg_integer().
score(_CFun, _A, _, W) when W =< 0 ->
  0;
score(CFun, A, Fun, W) when is_function(Fun) ->
  score(CFun, A, Fun(), W);
score(_CFun, _A, [], _W) ->
  0;
score(CFun, A, [B | L], W) ->
  case CFun(A, B) of
    true  -> 1;
    false -> score(CFun, A, L, W - 1)
  end.

%% Context management:

ctx_new(Size) ->
  #context{ size = Size
          , head = queue:new()
          , tail = queue:new()
          }.

ctx_push(A, Ctx = #context{size = Size, n = N, head = H0}) when N =:= Size - 1 ->
  {H, T} = queue:split(trunc(Size / 2), queue:in(A, H0)),
  Ctx#context{ n = N + 1
             , head = H
             , tail = T
             };
ctx_push(A, Ctx = #context{size = Size, n = N, head = H}) when N < Size ->
  Ctx#context{ n = N + 1
             , head = queue:in(A, H)
             };
ctx_push(A, Ctx = #context{n = N, tail = T0}) ->
  {_, T1} = queue:out(T0),
  T = queue:in(A, T1),
  Ctx#context{ n = N + 1
             , tail = T
             }.

ctx_to_list(#context{size = Size, n = N, head = Hd, tail = Tl}) when N =< Size ->
  queue:to_list(Hd) ++ queue:to_list(Tl);
ctx_to_list(#context{size = Size, n = N, head = Hd, tail = Tl}) ->
  NSkipped = N - Size,
  Placeholder = iolist_to_binary(io_lib:format("... omitted ~p elements ...", [NSkipped])),
  queue:to_list(Hd) ++ [Placeholder | queue:to_list(Tl)].

ctx_drop(#context{size = Size}) ->
  ctx_new(Size).
