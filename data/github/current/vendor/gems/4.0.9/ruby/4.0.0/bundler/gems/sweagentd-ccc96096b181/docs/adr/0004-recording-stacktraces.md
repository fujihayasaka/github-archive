# Recording Stacktraces

Status: accepted

Deciders: @chuxel @colbylwilliams @jasonetco  @josebalius

Related issue: https://github.com/github/sweagentd/issues/2373

## Context

The Go programming language does not record stacktraces on errors by default.  This means that if we want to display a stacktrace with an error in sentry, we need to generate it ourselves.  We've already implemented utilities in `sweagentd` for generating a stacktrace and attaching it to an error, and utilities for extracting that error when sending the error to sentry.  What we don't have yet is a convention for how these utilities should be used in the codebase.

## Decision

We propose two new functions:  

- `goerrors.New`, which is analogous to `errors.New`, but in addition to generating a new error, also attaches a stacktrace to it.
- `goerrors.Errorf`, which is analogous to `fmt.Errorf`, but in addition to wrapping an error with a contextual string, also checks to see if any errors being wrapped already contain a stacktrace.  If a stacktrace is not found, a stacktrace is also added.

These two utilities are designed so that they can replace `errors.New` and `fmt.Errorf` everywhere in the code, and ensure a single stacktrace either at error generation, or the first place the error is wrapped in our code (typically at the boundary of a third-party API).

In order to enforce usage of these utilities we also propose a custom linter `goerrorslint`.  This linter will scan for all uses of `errors.New` and `fmt.Errorf` present inside of functions, and suggest a change to `goerrors.New` and `goerrors.Errorf` respectively.  This will enforce usage of these functions to virtually guarantee our errors contains stacktraces.

One limitation of this approach is that we still want to support `errors.New` as package-level variables:

```
var errNotFound = errors.New("this widget was not found")
```

This is useful for calling code to be able to compare to this via `errors.Is`, and we obviously don't want to attach a stacktrace to an error that's generated during package initialization.  In these cases, it is up to the developer to add a stacktrace to the error themselves when the error is returned.

A PR has already been written that contains these helper functions, the custom linter, and an example of this being used in the `internal/spokes` package:  https://github.com/github/sweagentd/pull/7706

## Alternatives considered

As an alternative we could simply allow for manual wrapping of errors `goerrors.WithStack` when a stacktrace is desirable.  However, because it is hard to determine when an error should or should not have a stacktrace attached, it seemed a better developer experience to simply provide functions that can be used everywhere.

## Implications

Adding stacktraces to errors is not a zero-cost calculation, although it is cheaper in the current version of go than it used to be.  However, we are committing to a possible performance hit when adding stacktraces to errors.  Additionally checking to see if an error already has a stacktrace when wrapping errors involves traversing the error stack until a stacktrace is found.  That said, we assume that for the vast majority of the time that we return errors, that this is not the "hot path" and therefore shouldn't hugely affect average performance of our service.

### Additional details

OPTIONAL: This section can be used to provide implementation details, examples, future plans, etc.
