# Coding Style

In general, we use the default coding style enforced by `gofmt`.
We also try to following the patterns described in [Effective Go](https://golang.org/doc/effective_go).
This document describes additional coding style guidelines, and their reasoning.

In general, we try to keep our coding style light.
Everything is open for review or discussion!
If you have a contribution you'd like to make, open a PR and lets chat about it.

## Errors

Following guidance laid out by Dave Cheney in [Stack traces and the errors package](https://dave.cheney.net/2016/06/12/stack-traces-and-the-errors-package),
as well as other Go conventions,
we have the following guidelines for errors and error handling:

1. In our code, always use `github.com/pkg/errors.New` or `github.com/pkg/errors.Errorf` to create new errors.
2. Error messages should start with a lower-case letter and not include ending punctuation (`.`, `!`, etc.) so they can be composed cleanly, for example:
   * Avoid: `errors.Wrapf(errors.New("Inner error!"), "Outer error.")` ==> `Outer error.: Inner error!`
   * Prefer: `errors.Wrapf(errors.New("inner error"), "outer error")` ==> `outer error: inner error`
3. When we receive an error from a function in an external package (mysql, hydro, etc.), wrap it:
   1. If we have no useful context to add beyond the stack trace, use `github.com/pkg/errors.WithStack()`
   2. If we have useful context to add, use `github.com/pkg/errors.Wrap()` which allows us to attach **both** a stack trace and a message
4. When we receive an error from a function within our module and can retry or recover, do so in-place.
5. When we receive an error from a function within our module and cannot recover, simply return it (it should already have a stack trace and context)
6. Log and report errors at the top-level of the relevant worker (Consume handler in the consumer, HTTP handler for requests, etc.)
7. Avoid importing `errors` (the standard library errors package) into our files to avoid confusion. The `github.com/pkg/errors` package re-exports all of the APIs from that package.
8. Avoid using `fmt.Errorf`, as it doesn't produce a stacktrace. The `Errorf` function in `github.com/pkg/errors` is equivalent and provides a stacktrace.
9. Avoid using `err == SomeSentinelValue` to compare errors. Instead, use `errors.Is(err, SomeSentinelValue)`, which checks if any error in the chain of errors (following `.Unwrap` and `.Cause`) matches the sentinel value.

We don't currently have a linter to check these, but feel free to contribute one if you find/build one!

## Logging

1. Avoid using `fmt` methods to generate log messages. If you have parameters to add, add them with `kvp` fields.
   * Avoid: `logger.Info(fmt.Sprintf("processing item %d", itemId))`
   * Prefer: `logger.Info("processing item", kvp.Int("item_id", itemId))`
2. Include unique operation or request IDs in logs where possible, and use `diagnostics.WithLoggerFields` to attach them early so that later logger commands get them for free.
3. Don't start log messages with a capital letter, and avoid ending punctuation (`.`, `!`, etc.) for consistency.

## Context

Go's [`context.Context`](https://golang.org/pkg/context/) object is designed to provide "request-scoped" information like deadlines, cancellation signals, etc.
We use it to carry diagnostic reporting services like logging, metrics and error reporting as well.
In general:

1. Avoid capturing a `context.Context` on to a struct, instead pass it through function parameters.
2. Place loggers, statters, and reporters in the `Context` using the functions in the `diagnostics` package.
3. Apply additional tags using the functions in the `diagnostics` package when new context becomes available so that down-stack calls will attach them to logs/stats.
4. If your function takes a `context.Context`, pull the logger/statter/reporters you need from that.
