# 24. Consistent error handling in Go

Date: 2021-03-03

## Status

Accepted

## Context

Our error handling/modelling is fairly inconsistent throughout authnd.
Many errors are missing stack traces, because they were not created with stack-capturing mechanisms.
We're using a mix of the standard "errors" module, the "github.com/pkg/errors" module, and custom error types.
We have retry logic (or in this case, [a placeholder for future retry logic](https://github.com/github/authnd/blob/d88d129927af59eb211fe6e930dcefeec218030c/internal/replicator/consumer.go#L176)) far away from the context of the action that caused the retryable-error.

## Decision

Following guidance laid out by Dave Cheney in [Stack traces and the errors package](https://dave.cheney.net/2016/06/12/stack-traces-and-the-errors-package),
we'll adopt the following "rules" for error handling:

1. In our code, always use `github.com/pkg/errors.New` or `github.com/pkg/errors.Errorf` to create new errors.
2. When we receive an error from a function in an external package (mysql, hydro, etc.), wrap it:
   1. If we have no useful context to add beyond the stack trace, use `github.com/pkg/errors.WithStack()`
   2. If we have useful context to add, use `github.com/pkg/errors.Wrap()` which allows us to attach **both** a stack trace and a message
3. When we receive an error from a function within our module and can retry or recover, do so in-place.
4. When we receive an error from a function within our module and cannot recover, simply return it (it should already have a stack trace and context)
5. Log and report errors at the top-level of the relevant worker (Consume handler in the consumer, HTTP handler for requests, etc.)
6. Remove `ReplicationState` and custom error values and instead use `errors.New`-based errors and sentinel values unless absolutely necessary.

In addition, we should:

1. Avoid importing `errors` (the standard library errors package) into our files to avoid confusion. The `github.com/pkg/errors` package re-exports all of the APIs from that package.
2. Avoid using `fmt.Errorf`, as it doesn't produce a stacktrace. The `Errorf` function in `github.com/pkg/errors` is equivalent and provides a stacktrace.
3. Consider adopting a linter such as [wrapcheck](https://github.com/tomarrell/wrapcheck) to check the above rules to reduce code review burden.

## Consequences

### Wrap external errors in WithStack when we first see them

By always using `github.com/pkg/errors` to create or wrap errors as soon as we first see them, we get a full stacktrace attached at the moment we saw the error.
In many cases, the stack trace is sufficient context for the error and no additional context is needed.
For example, consider code like this:

```go
func tryDecryptAesPayload(ivText string, encryptedText string, encryptionKey string) ([]byte, error) {
    // ...
    ivBytes, err := base64.StdEncoding.DecodeString(ivText)
    if err != nil {
        return nil, err
    }
    // ...
```

As-is, the returned error will have no context to help us identify where it came from.
However, wrapping in an error like `error decoding IV: ...` is essentially just an artificial proxy on top of a stacktrace which would tell us exactly where the error occurred within our codebase.
Other "context" values such as the [`ReplicationState`](https://github.com/github/authnd/blob/d88d129927af59eb211fe6e930dcefeec218030c/internal/replicator/common/errors.go#L12) value similarly serve as rough proxies for the stacktrace.
Given that, we might as well just attach a stacktrace to *every* error at the moment we first see it in our package:

```go
func tryDecryptAesPayload(ivText string, encryptedText string, encryptionKey string) ([]byte, error) {
    // ...
    ivBytes, err := base64.StdEncoding.DecodeString(ivText)
    if err != nil {
        return nil, errors.WithStack(err)
    }
    // ...
```

### Wrap external errors in Wrap when we have non-stack-related context to add

Consider a case like this:

```go
func (r *replicator) UpsertPayload(sourceTableName string, kafkaOffset int64, binlogPosition string, gtid string, timestamp time.Time, shouldSetActiveSyncState bool, payload []byte) error {
    // ...
	return mysql.WithTransaction(r.db, func(tx *sql.Tx) error {
        // ...
		exists, err := checkReplicationSyncValues(tx, r.statter, destinationTable, kafkaOffset, gtid, id)
		if err != nil {
			return err
		}
        // ...
    }
}
```

Here, we likely **do** have additional context that is not captured in the stack trace: The table names, kafka offsets, etc.
Perhaps these values are clear from the stack trace, but in this situation it's better to presume that isn't the case.
For these cases, we can use `errors.Wrap` (and `errors.Wrapf`), which wrap errors **and** include a stacktrace:

```go
func (r *replicator) UpsertPayload(sourceTableName string, kafkaOffset int64, binlogPosition string, gtid string, timestamp time.Time, shouldSetActiveSyncState bool, payload []byte) error {
    // ...
	return mysql.WithTransaction(r.db, func(tx *sql.Tx) error {
        // ...
		exists, err := checkReplicationSyncValues(tx, r.statter, destinationTable, kafkaOffset, gtid, id)
		if err != nil {
			return errors.Wrapf(err, "error checking sync values for id '%d' in table '%s'", id, destinationTable)
		}
        // ...
    }
}
```

In this case, the `id` and `destinationTable` values are useful context since they are parameters that could not be inferred from the stack trace.
The Kafka offset is likely not useful here, or could be added by the code that reports the error, since it would be in the Consume handler (which has the Kafka offset already).
In general, add context that is only known at the point the error is seen.

### Retry errors in-place

Suggestion: Read the [package documentation for `github.com/pkg/errors`](https://pkg.go.dev/github.com/pkg/errors) for added context.
Particularly, the `errors.Is` function, which provides a way to find any error in a chain of wrapping errors that matches the provided value.
That function effectively allows you to take an error and identify if one of the root causes matches a particular type of error.

Finally, implementing retries at the site of the error allows us to ensure we have the appropriate information necessary to decide **if** a retry is appropriate.
Currently, we have a placeholder for retry logic in the replicator in the Consume handler.
Errors emitted lower in the stack include a value indicating if they should be retried so that the outer code knows if a retry should occur.
However, this requires us to attach additional context to errors, only to consume that context in our own code.
Instead, we should use retry helpers (either our own or from another package) to retry operations in place, where we know they can be retried.
For example, consider the same `UpsertPayload` function from above.
If we know that particular errors returned by `checkReplicationSyncValues` can be retried, such as `mysql.ErrInvalidConn` for example,
then we should retry that operation in-place, if possible.
For example:

```go
// Consider this hypothetical retry helper
//
// It retries the provide func as long as the error that is returned is caused by one of the provided retryable errors.
func RetryOn(fn func() error, retryableErrors ...error);

func (r *replicator) UpsertPayload(sourceTableName string, kafkaOffset int64, binlogPosition string, gtid string, timestamp time.Time, shouldSetActiveSyncState bool, payload []byte) error {
    // ...
	return mysql.WithTransaction(r.db, func(tx *sql.Tx) error {
        // ...
		exists, err := RetryOn(
            func() {
                return checkReplicationSyncValues(tx, r.statter, destinationTable, kafkaOffset, gtid, id)
            },
            mysql.ErrInvalidConn)
		if err != nil {
			return errors.Wrapf(err, "error checking sync values for id '%d' in table '%s'", id, destinationTable)
		}
        // ...
    }
}
```

### Linting

It will likely be difficult to enforce these rules solely by code review, and having code reviewers act as linters is a waste of valuable engineering time :).
We should look at linters like [`wrapcheck`](https://github.com/tomarrell/wrapcheck) to help us adhere to these rules.
Currently there are some minor issues with it that would block adoption but we could quickly fix those in a fork (and consider contributing upstream).
The main issue is that it treats any error that occurs outside the current *package* as needing wrapping.
However, we rarely (if every) need to wrap errors that occurred within another *package* inside our *module*.
