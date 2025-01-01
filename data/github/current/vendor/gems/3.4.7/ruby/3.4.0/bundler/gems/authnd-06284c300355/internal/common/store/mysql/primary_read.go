package mysql

import (
	"context"
	"database/sql"
	"strconv"

	"github.com/github/authnd/internal/common/diagnostics"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// ContextPrimaryReadsOnError returns a context which will cause the executor to fallback to mysql primary on
// read requests which return one of the specified errors on a mysql replica.  When the cluster has high replication lag,
// the executor will try a replica first, then fallback to primary if one of the provided errors is returned.
//
// This is the default policy with sql.ErrNoRows as the only fallback error.
func ContextPrimaryReadsOnError(ctx context.Context, fallbackErrors ...error) context.Context {
	policy, ok := ctx.Value(primaryReadPolicyContextKey{}).(*primaryReadPolicy)
	if !ok {
		policy = &primaryReadPolicy{}
	}
	policy.fallbackErrors = fallbackErrors

	return context.WithValue(ctx, primaryReadPolicyContextKey{}, policy)
}

// ContextPrimaryReadFallbackOnLag returns a context which will cause the executor preemptively read from primary in the
// presence of high replication lag.
func ContextPrimaryReadFallbackOnLag(ctx context.Context) context.Context {
	policy, ok := ctx.Value(primaryReadPolicyContextKey{}).(*primaryReadPolicy)
	if !ok {
		policy = &primaryReadPolicy{}
	}
	policy.skipReplicaRead = true
	policy.skipFreno = false

	return context.WithValue(ctx, primaryReadPolicyContextKey{}, policy)
}

// ContextPrimaryReadFallbackAlways returns a context which will cause the executor preemptively read from primary
// regardless of replication lag.  Primarily used in cases of frequent read-your-own-writes (e.g. AuthenticationTokens).
func ContextPrimaryReadFallbackAlways(ctx context.Context) context.Context {
	policy, ok := ctx.Value(primaryReadPolicyContextKey{}).(*primaryReadPolicy)
	if !ok {
		policy = &primaryReadPolicy{}
	}
	policy.skipReplicaRead = false
	policy.skipFreno = true

	return context.WithValue(ctx, primaryReadPolicyContextKey{}, policy)
}

type primaryReadPolicyContextKey struct{}

type primaryReadPolicy struct {
	fallbackErrors  []error
	skipReplicaRead bool
	skipFreno       bool
}

// NewPrimaryReadsExecutor executor implementation which can read from primary during periods of high replication lag.  When the provided
// freno.Throttler returns false from CanWrite, the executor will either preemptively read from primary or fallback to primary, based on the
// policy configured in the context.
func NewPrimaryReadsExecutor(replica, primary Executor, throttler freno.Throttler) Executor {
	return &primaryReadsExecutor{
		replica:   replica,
		primary:   primary,
		throttler: throttler,
	}
}

type primaryReadsExecutor struct {
	replica   Executor
	primary   Executor
	throttler freno.Throttler
}

func (e *primaryReadsExecutor) ConnectionName() string {
	return e.replica.ConnectionName() + "/" + e.primary.ConnectionName()
}

func (e *primaryReadsExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return e.withPrimaryReads(ctx, func(ex Executor) error {
		return ex.GetContext(ctx, dest, query, args...)
	})
}

func (e *primaryReadsExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return e.withPrimaryReads(ctx, func(ex Executor) error {
		return ex.SelectContext(ctx, dest, query, args...)
	})
}

func (e *primaryReadsExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	var row Row
	if err := e.withPrimaryReads(ctx, func(ex Executor) error {
		row = ex.QueryRowxContext(ctx, query, args...)
		return row.Err()
	}); err != nil {
		return &errorRow{err: err}
	}
	return row
}

func (e *primaryReadsExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return nil, errors.New("ExecContext should never be called on a primary reads executor!")
}

func (e *primaryReadsExecutor) unwrap() (*sqlx.DB, error) {
	return e.replica.unwrap()
}

func (e *primaryReadsExecutor) withPrimaryReads(ctx context.Context, fn func(Executor) error) error {
	statter := diagnostics.Statter(ctx)
	tags := stats.Tags{
		"policy": "fallback",
		"role":   "replica",
	}

	policy, ok := ctx.Value(primaryReadPolicyContextKey{}).(*primaryReadPolicy)
	if !ok {
		// no fallback policy set. use "row not found" as the default.
		policy = &primaryReadPolicy{
			fallbackErrors: []error{sql.ErrNoRows},
		}
	}
	if policy.skipReplicaRead {
		tags["policy"] = "read_from_primary"
	}

	var canWrite bool
	if !policy.skipFreno {
		var frenoErr error
		canWrite, frenoErr = e.throttler.CanWrite(ctx)
		if frenoErr != nil {
			// can't tell if the cluster is health, so "fail closed" and read from replica
			tags["freno_error"] = "true"
			statter.Counter("mysql.primary_reads_executor.read", tags, 1)
			return fn(e.replica)
		}
		tags["freno_ok"] = strconv.FormatBool(canWrite)
	} else {
		tags["freno_ok"] = "skipped"
	}

	if canWrite {
		// cluster is known to have low replication lag, just read from replica with no fallback
		statter.Counter("mysql.primary_reads_executor.read", tags, 1)
		return fn(e.replica)
	}

	// freno report high replication lag or was explicitly skipped
	if !policy.skipReplicaRead {
		// try to read from replica first
		statter.Counter("mysql.primary_reads_executor.read", tags, 1)
		err := fn(e.replica)
		if err == nil || !errorIsOneOf(err, policy.fallbackErrors...) {
			// error is not eligible for fallback (or no error)
			return err
		}
	}

	tags["role"] = "primary"
	statter.Counter("mysql.primary_reads_executor.read", tags, 1)
	return fn(e.primary)
}

func errorIsOneOf(err error, targets ...error) bool {
	for _, e := range targets {
		if errors.Is(err, e) {
			return true
		}
	}
	return false
}
