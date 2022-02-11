# Offline analysis of the traces

Even though philosophy of this library lies in separation of run and verify stages, sometimes the former needs to be aware of the events.
For example, the testcase may need to wait for asynchronous initialization of some resource.

## block_until

In this case `?block_until` macro should be used. It allows the testcase to peek into the trace. Example usage:

#+BEGIN_SRC erlang
?block_until(#{?snk_kind := Kind}, Timeout, BackInTime)
#+END_SRC

Note: it's tempting to use this macro to check the result of some
asynchronous action, like this:

#+BEGIN_SRC erlang
{ok, Pid} = foo:async_init(),
{ok, Event} = ?block_until(#{?snk_kind := foo_init, pid := Pid}),
do_stuff(Pid)
#+END_SRC

However it's not a good idea, because the event can be emitted before
=?block_until= has a chance to run. Use the following macro to avoid
this race condition:

#+BEGIN_SRC
{{ok, Pid}, {ok, Event}} = ?wait_async_action( foo:async_init()
                                             , #{?snk_kind := foo_init, pid := Pid}
                                             ),
do_stuff(Pid)
#+END_SRC


## wait_async_action

```erlang
-module(offline_analysis_example).

-include_lib("eunit/include/eunit.hrl").
-include_lib("snabbkaffe/include/snabbkaffe.hrl").

```
