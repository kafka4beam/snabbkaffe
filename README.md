Snabbkaffe
==========

> If humans can find bugs by reading the logs, so can computers

[Read the documentation for the latest version.](https://kafka4beam.github.io/snabbkaffe-docs)

Snabbkaffe is a trace-based test framework for Erlang.
It is lightweight and dependency-free.

It works like this:

 1) Programmer manually instruments the code with trace points
 2) Testcases are split in two parts:
    - *Run stage* where the program runs and emits event trace
    - *Check stage* where trace is collected and validated against the spec(s)
 3) Trace points become structured log messages in the release build

This approach can be used in a component test involving an ensemble of interacting processes. It has a few nice properties:

 + Checks can be separated from the program execution
 + Checks are independent from each other and fully composable
 + Trace contains complete history of the process execution, thus making certain types of concurrency bugs, like livelocks, easier to detect

Additionally, snabbkaffe supports fault and delay injection into the system to test correctness of the supervision trees and rare code paths.

## Getting started

Add the following to `rebar.config`:

```erlang
{deps, [{snabbkaffe, {git, "https://github.com/kafka4beam/snabbkaffe.git", {tag, "1.0.0"}}}]}.
```
