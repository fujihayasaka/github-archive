package mysqldb

import (
	"context"
	"database/sql"
	"testing"

	"github.com/go-sql-driver/mysql"
	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability/statter"
)

var deadlockErr = &mysql.MySQLError{
	Number:  deadlockErrorCode,
	Message: "Deadlock found",
}

var serverShutdownErr = &mysql.MySQLError{
	Number:  ServerShutdownErrorCode,
	Message: "Server shutdown in progress",
}

func TestWithDeadlockRetriesDeadlocks(t *testing.T) {
	t.Parallel()

	results := []error{
		deadlockErr,
		deadlockErr,
		nil,
	}

	callI := 0
	workFn := func() (sql.Result, error) {
		if callI > len(results) {
			t.Errorf("Too many calls, expected at most %v", len(results))
		}

		i := callI
		callI++
		return nil, results[i]
	}

	_, err := WithDeadlockRetry(context.Background(), "te", statter.NullStatter(), workFn)

	require.NoError(t, err)
	assert.Equal(t, 3, callI)
}

func TestWithDeadlockRetriesServerShutdowns(t *testing.T) {
	t.Parallel()

	results := []error{
		serverShutdownErr,
		serverShutdownErr,
		nil,
	}

	callI := 0
	workFn := func() (sql.Result, error) {
		if callI > len(results) {
			t.Errorf("Too many calls, expected at most %v", len(results))
		}

		i := callI
		callI++
		return nil, results[i]
	}

	_, err := WithDeadlockRetry(context.Background(), "te", statter.NullStatter(), workFn)

	require.NoError(t, err)
	assert.Equal(t, 3, callI)
}

func TestWithDeadlockStopsOnError(t *testing.T) {
	t.Parallel()

	boomErr := errs.New("boom")

	results := []error{
		deadlockErr,
		boomErr,
		deadlockErr,
		deadlockErr,
		deadlockErr,
		deadlockErr,
		deadlockErr,
	}

	callI := 0
	workFn := func() (sql.Result, error) {
		if callI > len(results) {
			t.Errorf("Too many calls, expected at most %v", len(results))
		}

		i := callI
		callI++
		return nil, results[i]
	}

	_, err := WithDeadlockRetry(context.Background(), "te", statter.NullStatter(), workFn)

	assert.EqualError(t, err, "boom")
}
