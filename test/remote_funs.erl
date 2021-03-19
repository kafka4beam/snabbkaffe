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

remote_metadata() ->
  logger:update_process_metadata(#{ domain => [remote]
                                  , meta1 => foo
                                  , meta2 => bar
                                  }),
  ?tp(foo, #{}),
  ?tp(bar, #{}).

remote_stats() ->
  snabbkaffe:push_stat({foo, 1}, 1, 1).
