-module(remote_funs).

-compile(export_all).

-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("stdlib/include/assert.hrl").

remote_tp() ->
  spawn(
    fun() ->
        ?tp(remote_bar, #{node => node()})
    end),
  ?tp(remote_foo, #{node => node()}).

remote_crash() ->
  ?assertError(notmyday, ?tp(remote_fail, #{})).

remote_delay() ->
  spawn(
    fun() ->
        ?tp(bar, #{id => 1})
    end),
  spawn(
    fun() ->
        ?tp(bar, #{id => 2})
    end),
  ok.
