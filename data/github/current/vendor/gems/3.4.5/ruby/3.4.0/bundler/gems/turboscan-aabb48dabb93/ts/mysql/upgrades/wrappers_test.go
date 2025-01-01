package upgrades

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/stretchr/testify/require"
)

func TestWithRetry(t *testing.T) {
	// retry temporary errors
	{
		count := 0
		require.NoError(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
			count += 1
			if attempt < 5 {
				return mysql.ErrInvalidConn
			}
			return nil
		}))
		require.Equal(t, 5, count)
	}
	// retry non-temporary errors once only
	{
		count := 0
		require.ErrorIs(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
			count += 1
			// return an error we should not retry
			return io.EOF
		}), io.EOF)
		require.Equal(t, 2, count)
	}
	// return a non-temporary error after a temporary one
	{
		count := 0
		require.ErrorIs(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
			count += 1
			if attempt == 1 {
				return mysql.ErrInvalidConn
			}
			return io.EOF
		}), io.EOF)
		require.Equal(t, 2, count)
	}
	// ignore non-temporary errors once only
	{
		count := 0
		require.NoError(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
			count += 1
			if attempt == 1 {
				return io.EOF
			}
			return nil
		}))
		require.Equal(t, 2, count)
	}
	//  no error
	{
		count := 0
		require.NoError(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
			count += 1
			return nil
		}))
		require.Equal(t, 1, count)
	}
}

func TestWithStopRetry(t *testing.T) {
	count := 0
	require.ErrorIs(t, withRetry(context.Background(), 0*time.Second, func(attempt int) error {
		count += 1
		if attempt < 5 {
			return mysql.ErrInvalidConn
		}
		// this error is not temporary and should not be retried
		return io.EOF
	}), io.EOF)
	require.Equal(t, 5, count)
}

func TestWithDynamicRetry(t *testing.T) {
	count := 0
	expected := [][]uint64{
		{1, 10},
		{1, 10},
		{1, 5},
		{1, 3},
		{1, 2},
		{1, 1},
		{1, 1},
	}
	require.NoError(t, withDynamicRetry(context.Background(), 0*time.Second, 1, 10, func(start, end uint64) error {
		if count >= len(expected) {
			return nil
		}
		require.Equal(t, expected[count], []uint64{start, end}, "iteration %d", count)
		count += 1
		// return a temporary error that is handled by withDynamicRetry
		return &mysql.MySQLError{Number: 1153, Message: "Packet bigger than max size allowed"}
	}))
	require.Equal(t, 7, count)
}

func TestWithDynamicRetryTemporaryError(t *testing.T) {
	count := 0
	require.NoError(t, withDynamicRetry(context.Background(), 0*time.Second, 1, 10, func(start, end uint64) error {
		// return a temporary error that is not handled by withDynamicRetry
		if count += 1; count < 10 {
			return mysql.ErrInvalidConn
		}
		return nil
	}))
	require.Equal(t, 10, count)
}

func TestWithDynamicRetryPermanentError(t *testing.T) {
	count := 0
	var err *mysql.MySQLError
	require.ErrorAs(t, withDynamicRetry(context.Background(), 0*time.Second, 1, 10, func(start, end uint64) error {
		count += 1
		// return a non-temporary error
		return &mysql.MySQLError{Number: 1064, Message: "syntax error"}
	}), &err)
	// we will retry a non-temporary error once only
	require.Equal(t, 2, count)
}
